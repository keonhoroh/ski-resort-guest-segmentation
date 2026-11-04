-- One row per guest. Small table (~100k rows), sorted by guest_id for fast lookups.
CREATE TABLE IF NOT EXISTS guests
(
    guest_id     UInt64,
    pass_type    LowCardinality(String),  -- season, multi_day, day
    skill_level  LowCardinality(String),  -- beginner, intermediate, advanced, expert
    home_region  LowCardinality(String),
    email_opt_in UInt8,                   -- 1 = agreed to marketing email
    signup_date  Date
)
ENGINE = MergeTree
ORDER BY guest_id;
