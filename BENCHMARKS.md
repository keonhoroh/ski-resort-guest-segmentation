# Benchmarks

How fast the three example segments are counted, and how much data ClickHouse reads to count them, from three ways of storing the same events.

## Setup

| | |
|---|---|
| Machine | Apple M1 Pro, 10 cores, 32 GB RAM |
| ClickHouse | 26.8.36.3 in Docker Desktop (VM limited to 10 CPUs, 7.7 GiB RAM) |
| Data | 100,000 guests and 10,000,000 events (`SCALE=full`), one ski season: 2025-11-27 to 2026-04-12 |
| Method | `bin/rails bench:segments`: one warm-up run, then 5 measured runs per segment. Times are the median `query_duration_ms`; rows and data read come from `system.query_log`. |

"Data read" is uncompressed bytes. "Rows read" includes the 100,000-row `guests` table that every query reads once.

## The three tables

| Table | How it is stored | Rows | On disk |
|---|---|---:|---:|
| `events_baseline` | Rows shuffled, no sort key (`ORDER BY tuple()`), no partitions. A deliberately weak design. | 10,000,000 | 97.80 MiB |
| `events` | `PARTITION BY toYYYYMM(event_time)`, `ORDER BY (guest_id, event_time)` | 10,000,000 | 62.36 MiB |
| `daily_event_counts` | Daily rollup kept up to date by a materialized view. `SummingMergeTree`, `ORDER BY (event_type, difficulty, event_date, guest_id)` | 2,304,123 | 14.44 MiB |

The rollup size is after `OPTIMIZE TABLE ... FINAL`. Its `events` column adds up to exactly 10,000,000, and a full comparison against `events` found no differing guest/day/type counts.

## Results

| Source | Segment | Guests | Median ms | Rows read | Data read |
|---|---|---:|---:|---:|---:|
| `events_baseline` | Season pass, lapsed 30 days | 62 | 54 | 10,100,000 | 115 MB |
| `events_baseline` | 50+ expert scans in 120 days | 6,503 | 59 | 10,100,000 | 134 MB |
| `events_baseline` | Lesson, no visit in 14 days | 25,485 | 83 | 20,100,000 | 239 MB |
| `events` | Season pass, lapsed 30 days | 62 | 30 | 10,100,000 | 115 MB |
| `events` | 50+ expert scans in 120 days | 6,503 | 55 | 9,808,996 | 130 MB |
| `events` | Lesson, no visit in 14 days | 25,485 | 57 | 20,100,000 | 239 MB |
| `daily_event_counts` | Season pass, lapsed 30 days | 62 | 28 | 2,404,123 | 22.8 MB |
| `daily_event_counts` | 50+ expert scans in 120 days | 6,503 | 14 | 427,680 | 7.01 MB |
| `daily_event_counts` | Lesson, no visit in 14 days | 25,485 | 36 | 2,510,619 | 24.7 MB |

A second full run of the benchmark was within 3 ms of these times, with identical rows and data read. All three sources return the same guest counts.

## What changed the rows read

**Sort key alone (`events_baseline` → `events`): almost no change in rows read.** Every rule asks a question about every guest over most of the season, so ClickHouse has to read nearly every event whatever the order. The one saving is partition pruning: the 120-day window starts on 2025-12-14, so the November partition (291,004 rows) is skipped entirely. The sort key still cut times by up to 45%, because each guest's events sit together, which makes `GROUP BY guest_id` cheaper, and sorted data compressed to 62 MiB instead of 98 MiB.

**Rollup (`events` → `daily_event_counts`): 4 to 23 times fewer rows read.** Two separate effects:

1. **Fewer rows.** One row per guest, day, event type, and difficulty replaces every individual event: 2.3 million rows instead of 10 million. Rules with no event-type filter, like "no visit in 30 days", still read the whole rollup, but it is a quarter of the size.
2. **A sort key that matches the filters.** The rollup is sorted by `event_type, difficulty, event_date` first, so for "expert lift scans since 2025-12-14" ClickHouse uses the primary index to skip straight to that range. It read 40 granules of 8,192 rows (327,680 rows) plus the guests table, instead of all 9.8 million events.

The rollup gives exactly the same answers as the raw events because every rule's time limit falls on midnight, so a rule never needs part of a day. The specs check this by running every rule against both tables, including day counts that land just before, on, and just after the fixture's event dates.

## Reproduce

```sh
SCALE=full bin/rails clickhouse:generate
bin/rails bench:baseline   # builds events_baseline (only needed for the comparison)
bin/rails bench:segments
```
