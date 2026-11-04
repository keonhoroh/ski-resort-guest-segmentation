# A tiny hand-made dataset where we know the right answers.
#
# "Today" for these tests is AS_OF (the last day of the season). Each guest is
# built to land in, or narrowly miss, one of the three example segments:
#
#   A. Season pass holders who have not visited in 30 days   → guests 2, 3
#   B. 50+ expert lift scans in the last 120 days             → guest 1
#   C. Took a lesson, but no visit in the last 14 days        → guest 4
#
# Usage in a spec:  before { ClickhouseFixtures.load! }
module ClickhouseFixtures
  AS_OF = Date.new(2026, 4, 12)

  EXPECTED = {
    season_lapsed_30_days: [ 2, 3 ],
    expert_scans_50_in_120_days: [ 1 ],
    lesson_not_returned_14_days: [ 4 ]
  }.freeze

  # The same three segments, written as segment rules.
  SEGMENTS = {
    season_lapsed_30_days: {
      "match" => "all",
      "rules" => [
        { "type" => "attribute", "field" => "pass_type", "operator" => "eq", "value" => "season" },
        { "type" => "last_event", "operator" => "older_than", "days" => 30 }
      ]
    },
    expert_scans_50_in_120_days: {
      "match" => "all",
      "rules" => [
        { "type" => "event_count", "event" => "lift_scan", "difficulty" => "expert",
          "operator" => "gte", "value" => 50, "window_days" => 120 }
      ]
    },
    lesson_not_returned_14_days: {
      "match" => "all",
      "rules" => [
        { "type" => "event_count", "event" => "lesson", "operator" => "gte", "value" => 1 },
        { "type" => "last_event", "operator" => "older_than", "days" => 14 }
      ]
    }
  }.freeze

  GUESTS = [
    # id, pass, skill, region, opt-in
    [ 1, "season",    "expert",       "Northeast",     1 ], # 60 expert scans, last visit 2 days ago → B
    [ 2, "season",    "intermediate", "Mid-Atlantic",  1 ], # last visit 51 days ago → A
    [ 3, "season",    "advanced",     "Pacific",       0 ], # last visit in December, opted out of email → A
    [ 4, "day",       "beginner",     "Southeast",     1 ], # lesson 23 days ago, never returned → C
    [ 5, "multi_day", "beginner",     "Midwest",       1 ], # lesson, but returned 7 days ago → not C
    [ 6, "multi_day", "expert",       "Mountain West", 1 ], # 49 expert scans: one short of B
    [ 7, "season",    "expert",       "Canada",        1 ], # 50 expert scans, but 10 are older than 120 days → not B
    [ 8, "day",       "advanced",     "Northeast",     1 ], # 55 scans, but black runs, not expert → not B
    [ 9, "day",       "intermediate", "Pacific",       1 ]  # signed up, never visited
  ].freeze

  def self.events
    [
      scans(1, 60, "expert", on: "2026-04-10"),

      scans(2, 5, "blue", on: "2026-02-20"),

      scans(3, 3, "black", on: "2025-12-15"),

      event(4, "lesson", on: "2026-03-20"),
      scans(4, 2, "green", on: "2026-03-20"),

      event(5, "lesson", on: "2026-03-28"),
      scans(5, 4, "green", on: "2026-04-05"),

      scans(6, 49, "expert", on: "2026-03-01"),

      scans(7, 10, "expert", on: "2025-12-01"), # 132 days before AS_OF: outside the 120-day window
      scans(7, 40, "expert", on: "2026-04-05"),

      scans(8, 55, "black", on: "2026-03-15")
    ].flatten
  end

  def self.load!(client = ClickhouseClient.new)
    client.execute("TRUNCATE TABLE events")
    client.execute("TRUNCATE TABLE daily_event_counts") # refilled by the insert into events below
    client.execute("TRUNCATE TABLE guests")

    client.insert_rows("guests", GUESTS.map do |id, pass, skill, region, opt_in|
      { guest_id: id, pass_type: pass, skill_level: skill, home_region: region,
        email_opt_in: opt_in, signup_date: "2024-10-01" }
    end)
    client.insert_rows("events", events)
  end

  LIFT_FOR = { "green" => 1, "blue" => 5, "black" => 11, "expert" => 16 }.freeze

  # `count` lift scans on one day, one minute apart starting at 9:00.
  def self.scans(guest_id, count, difficulty, on:)
    Array.new(count) do |i|
      { event_time: "#{on} #{format('%02d:%02d', 9 + i / 60, i % 60)}:00", guest_id: guest_id,
        event_type: "lift_scan", lift_id: LIFT_FOR.fetch(difficulty), difficulty: difficulty }
    end
  end

  def self.event(guest_id, type, on:)
    { event_time: "#{on} 08:30:00", guest_id: guest_id, event_type: type, lift_id: 0, difficulty: "" }
  end
end
