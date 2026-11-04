# Guest Segment Builder

A guest segmentation tool for a fictional ski resort. A marketer builds a group of guests from rules (for example, "season pass holders who have not visited in 30 days"), sees the audience size update as they edit, saves the segment, and launches a campaign to it.

All data is synthetic. No real messages are sent.

## Stack

| Layer | Technology |
|---|---|
| API | Ruby on Rails 8.1 (API mode) |
| Web app | React, TypeScript, Vite |
| Event data | ClickHouse: 100,000 guests and 10 million events |
| App data | PostgreSQL: saved segments and campaigns |
| Background jobs | Sidekiq and Redis |
| Tests | RSpec |

## How it works

```
React page ──► Rails API ──► SegmentRules::Validator   (rejects anything not on the allow-list)
                         ──► SegmentRules::QueryBuilder (rules → parameterized SQL)
                         ──► ClickHouse                  (counts matching guests)
                         ──► PostgreSQL                  (stores saved segments and campaigns)
                         ──► Redis ──► Sidekiq           (SendCampaignJob runs in the background)
```

Segment rules are JSON:

```json
{
  "match": "all",
  "rules": [
    { "type": "attribute", "field": "pass_type", "operator": "eq", "value": "season" },
    { "type": "last_event", "operator": "older_than", "days": 30 }
  ]
}
```

User input never becomes SQL text. Fields and operators come from allow-lists, and every value is sent as a ClickHouse query parameter.

### Campaigns

Launching a campaign saves a `campaigns` row (with a copy of the segment's rules) and queues `SendCampaignJob`. The job fetches opted-in guest IDs from ClickHouse 1,000 at a time and records each simulated send in `campaign_sends`, updating progress after every batch.

The job is safe to retry. A unique index on `(campaign_id, guest_id)` means a guest can only be recorded once per campaign, a retry resumes after the last guest sent to, and `sent_count` is recounted from the rows rather than added to. The specs crash the job partway through and check that the retry finishes with the correct total.

## Project layout

| Path | What's there |
|---|---|
| `app/controllers/api/` | API endpoints |
| `app/models/` | PostgreSQL models (`Segment`, `Campaign`, `CampaignSend`) |
| `app/jobs/` | `SendCampaignJob` |
| `app/services/` | ClickHouse client, data generator, and the segment rules engine |
| `db/clickhouse/` | ClickHouse table definitions and data generation SQL |
| `db/migrate/` | PostgreSQL migrations |
| `lib/tasks/` | `clickhouse:*` commands |
| `spec/` | RSpec tests, including a hand-built fixture with known answers |
| `frontend/` | React app |
| `config/`, `bin/` | Standard Rails configuration and scripts |

## Running locally

You need Ruby 3.4, Node 22, and Docker.

```sh
cp .env.example .env              # then set the passwords
docker compose up -d              # ClickHouse, PostgreSQL, Redis
bundle install
bin/rails db:prepare              # PostgreSQL tables
SCALE=full bin/rails clickhouse:generate   # 10M events (or omit SCALE for 100k)

bin/rails server                  # API on http://localhost:3000
bundle exec sidekiq               # background jobs (in a second terminal)
cd frontend && npm install && npm run dev  # web app on http://localhost:5173
```

## Tests

```sh
bundle exec rspec
```

The tests use separate `liftline_test` databases, so they never touch development data.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/health` | Checks PostgreSQL, ClickHouse, and Redis |
| POST | `/api/segments/preview` | Audience count and query time for unsaved rules |
| GET | `/api/segments/options` | The allowed fields, operators, and values |
| GET, POST | `/api/segments` | List or create segments |
| GET, PATCH, DELETE | `/api/segments/:id` | Read, update, or delete a segment |
| POST | `/api/segments/:id/campaigns` | Launch a campaign to a segment |
| GET | `/api/campaigns` | List campaigns with progress |
| GET | `/api/campaigns/:id` | One campaign's progress |
