-- Creates {guests} synthetic guests, entirely inside ClickHouse.
--
-- "Random" choices are hashes of the row number (cityHash64(number, salt)),
-- so the same input always produces exactly the same guests.
--
--   pass_type:   15% season, 35% multi_day, 50% day
--   skill_level: 25% beginner, 35% intermediate, 28% advanced, 12% expert
--                (season pass holders skew more skilled: none are beginners)
--   email_opt_in: about 70% of guests
INSERT INTO guests (guest_id, pass_type, skill_level, home_region, email_opt_in, signup_date)
SELECT
    number + 1 AS guest_id,
    multiIf(pass_roll < 0.15, 'season', pass_roll < 0.50, 'multi_day', 'day') AS pass_type,
    multiIf(skill_roll < 0.25, 'beginner',
            skill_roll < 0.60, 'intermediate',
            skill_roll < 0.88, 'advanced',
            'expert') AS skill_level,
    ['Northeast', 'Mid-Atlantic', 'Southeast', 'Midwest', 'Mountain West', 'Pacific', 'Canada']
        [1 + cityHash64(number, 3) % 7] AS home_region,
    toUInt8(cityHash64(number, 4) % 100 < 70) AS email_opt_in,
    toDate('2019-01-01') + toIntervalDay(cityHash64(number, 5) % 2500) AS signup_date
FROM
(
    SELECT
        number,
        (cityHash64(number, 1) % 10000) / 10000 AS pass_roll,
        (cityHash64(number, 2) % 10000) / 10000 AS raw_skill_roll,
        -- Season pass holders start at 0.25, skipping the beginner range.
        if(pass_roll < 0.15, 0.25 + raw_skill_roll * 0.75, raw_skill_roll) AS skill_roll
    FROM numbers({guests:UInt64})
)
