-- Creates exactly {events} synthetic events for the guests already in `guests`,
-- entirely inside ClickHouse. Run guests.sql first.
--
-- How the data is shaped:
--   * Events come in visits of 14. Each visit is one guest on one day of the
--     2025-26 season: Thanksgiving (2025-11-27) to 2026-04-12, 137 days.
--   * Season pass holders get 64% of visits, multi-day 25%, day 11%,
--     so season pass holders visit far more often per person.
--   * Days are picked by weight: Saturdays x2.4, Sundays x2.0, Fridays x1.3,
--     holidays x2.8 (Thanksgiving weekend, Christmas week, MLK and Presidents'
--     Day weekends). November and April are quieter (x0.6), December x0.85.
--   * Skill level decides which runs a guest rides (beginners mostly green,
--     experts mostly black and expert) and how often they take lessons.
--   * Day pass guests rent equipment most often.
--
-- "Random" choices are hashes of the event or visit number, so the same inputs
-- always produce the same data. That keeps benchmarks repeatable.
INSERT INTO events (event_time, guest_id, event_type, lift_id, difficulty)
SELECT event_time, visit_guest_id, event_type, lift_id, difficulty
FROM
(
    WITH
        toDate('2025-11-27') AS season_start,
        arrayMap(i -> season_start + i, range(137)) AS season_days,
        arrayMap(d ->
            multiIf(
                d BETWEEN toDate('2025-12-24') AND toDate('2026-01-01'), 2.8,
                has([toDate('2025-11-28'), toDate('2025-11-29'), toDate('2025-11-30'),
                     toDate('2026-01-17'), toDate('2026-01-18'), toDate('2026-01-19'),
                     toDate('2026-02-14'), toDate('2026-02-15'), toDate('2026-02-16')], d), 2.8,
                toDayOfWeek(d) = 6, 2.4,
                toDayOfWeek(d) = 7, 2.0,
                toDayOfWeek(d) = 5, 1.3,
                1.0)
            * multiIf(toMonth(d) IN (11, 4), 0.6, toMonth(d) = 12, 0.85, 1.0),
            season_days) AS day_weights,
        arrayCumSum(day_weights) AS cumulative_weights,
        -- A 1000-slot lookup table: slot k holds the day where k/1000 of the total
        -- weight is reached. Busy days fill more slots, so they get picked more.
        arrayMap(k -> arrayFirstIndex(w -> w > (k + 0.5) / 1000 * cumulative_weights[-1],
                                      cumulative_weights),
                 range(1000)) AS day_lookup,
        -- Guests grouped by pass type, sorted so the result is repeatable.
        (SELECT arraySort(groupArray((guest_id, skill_level))) FROM guests WHERE pass_type = 'season')    AS season_guests,
        (SELECT arraySort(groupArray((guest_id, skill_level))) FROM guests WHERE pass_type = 'multi_day') AS multi_day_guests,
        (SELECT arraySort(groupArray((guest_id, skill_level))) FROM guests WHERE pass_type = 'day')       AS day_guests
    SELECT
        intDiv(number, 14) AS visit,

        -- Who: pick a pass type for the visit, then a guest with that pass type.
        cityHash64(visit, 1) % 100 AS group_roll,
        multiIf(group_roll < 64, 'season', group_roll < 89, 'multi_day', 'day') AS visit_pass,
        cityHash64(visit, 2) AS guest_roll,
        multiIf(visit_pass = 'season',    season_guests[1 + guest_roll % length(season_guests)],
                visit_pass = 'multi_day', multi_day_guests[1 + guest_roll % length(multi_day_guests)],
                                          day_guests[1 + guest_roll % length(day_guests)]) AS visit_guest,
        tupleElement(visit_guest, 1) AS visit_guest_id,
        tupleElement(visit_guest, 2) AS visit_skill,

        -- When: a weighted day for the visit, then a time between 8:30 and 16:00.
        season_days[day_lookup[1 + cityHash64(visit, 3) % 1000]] AS visit_day,
        toDateTime(visit_day, 'UTC') + toIntervalSecond(30600 + cityHash64(number, 4) % 27000) AS event_time,

        -- What: mostly lift scans, sometimes a lesson or a rental.
        (cityHash64(number, 5) % 10000) / 10000 AS type_roll,
        multiIf(visit_skill = 'beginner', 0.04, visit_skill = 'intermediate', 0.015,
                visit_skill = 'advanced', 0.005, 0.002) AS lesson_rate,
        multiIf(visit_pass = 'day', 0.05, visit_pass = 'multi_day', 0.03, 0.005) AS rental_rate,
        multiIf(type_roll < lesson_rate, 'lesson',
                type_roll < lesson_rate + rental_rate, 'rental',
                'lift_scan') AS event_type,

        -- Which run: cutoffs for (green, blue, black); the rest is expert.
        (cityHash64(number, 6) % 10000) / 10000 AS run_roll,
        multiIf(visit_skill = 'beginner',     (0.80, 0.98, 1.00),
                visit_skill = 'intermediate', (0.25, 0.80, 0.98),
                visit_skill = 'advanced',     (0.05, 0.35, 0.85),
                                              (0.02, 0.15, 0.55)) AS cutoffs,
        if(event_type = 'lift_scan',
           multiIf(run_roll < tupleElement(cutoffs, 1), 'green',
                   run_roll < tupleElement(cutoffs, 2), 'blue',
                   run_roll < tupleElement(cutoffs, 3), 'black',
                   'expert'),
           '') AS difficulty,

        -- Lifts 1-4 serve green runs, 5-10 blue, 11-15 black, 16-18 expert.
        cityHash64(number, 7) AS lift_roll,
        toUInt16(multiIf(difficulty = 'green',  1 + lift_roll % 4,
                         difficulty = 'blue',   5 + lift_roll % 6,
                         difficulty = 'black',  11 + lift_roll % 5,
                         difficulty = 'expert', 16 + lift_roll % 3,
                         0)) AS lift_id
    FROM numbers({events:UInt64})
)
