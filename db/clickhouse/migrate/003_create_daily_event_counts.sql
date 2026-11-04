-- A daily summary of events: one row per event type, difficulty, day, and guest,
-- holding how many events that was. Segment rules read this instead of the raw
-- events table, because it has far fewer rows and is sorted by what the rules
-- filter on, so ClickHouse can skip everything else.
--
-- events stays the source of truth. This table can be rebuilt from it at any time.
--
-- SummingMergeTree adds up rows with the same sort key when it merges parts in
-- the background. Merges happen whenever ClickHouse gets to them, so queries
-- must still use sum(events).
CREATE TABLE IF NOT EXISTS daily_event_counts
(
    event_type LowCardinality(String),
    difficulty LowCardinality(String),
    event_date Date,
    guest_id   UInt64,
    events     UInt64
)
ENGINE = SummingMergeTree
ORDER BY (event_type, difficulty, event_date, guest_id);

-- Keeps the summary up to date: every insert into events also inserts its
-- daily counts here.
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_event_counts_mv TO daily_event_counts AS
SELECT event_type, difficulty, toDate(event_time) AS event_date, guest_id, count() AS events
FROM events
GROUP BY event_type, difficulty, event_date, guest_id;

-- Backfill events that were stored before the view existed.
-- (Nothing else writes to events while migrations run.)
INSERT INTO daily_event_counts
SELECT event_type, difficulty, toDate(event_time) AS event_date, guest_id, count() AS events
FROM events
GROUP BY event_type, difficulty, event_date, guest_id;
