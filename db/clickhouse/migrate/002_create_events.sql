-- One row per thing a guest did: a lift scan, a lesson, or a rental.
-- This is the big table (10 million rows at full scale).
--
-- ORDER BY (guest_id, event_time) stores each guest's events together, in time
-- order, so "count this guest's events in the last N days" reads very little data.
-- PARTITION BY month splits the data into one chunk per month on disk.
CREATE TABLE IF NOT EXISTS events
(
    event_time DateTime('UTC'),
    guest_id   UInt64,
    event_type LowCardinality(String),  -- lift_scan, lesson, rental
    lift_id    UInt16,                  -- 0 for lessons and rentals
    difficulty LowCardinality(String)   -- green, blue, black, expert, or '' if not a lift scan
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (guest_id, event_time);
