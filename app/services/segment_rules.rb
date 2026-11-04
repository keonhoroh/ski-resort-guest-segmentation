# The allow-lists for segment rules: every field, operator, and event type the
# app understands. Anything not listed here is rejected by SegmentRules::Validator.
#
# A segment definition looks like:
#
#   {
#     "match": "all",                     # "all" = AND, "any" = OR
#     "rules": [
#       { "type": "attribute", "field": "pass_type", "operator": "eq", "value": "season" },
#       { "type": "event_count", "event": "lift_scan", "difficulty": "expert",
#         "operator": "gte", "value": 50, "window_days": 120 },
#       { "type": "last_event", "operator": "older_than", "days": 30 }
#     ]
#   }
module SegmentRules
  # Raised when QueryBuilder is handed rules that did not pass validation.
  class InvalidRules < StandardError; end

  MATCHES = { "all" => "AND", "any" => "OR" }.freeze

  # Guest columns a rule may compare, with their ClickHouse type and allowed values.
  ATTRIBUTES = {
    "pass_type" => { type: "String", values: %w[season multi_day day] },
    "skill_level" => { type: "String", values: %w[beginner intermediate advanced expert] },
    "home_region" => { type: "String",
                       values: [ "Northeast", "Mid-Atlantic", "Southeast", "Midwest",
                                 "Mountain West", "Pacific", "Canada" ] },
    "email_opt_in" => { type: "UInt8", values: [ true, false ] }
  }.freeze

  ATTRIBUTE_OPERATORS = %w[eq neq in].freeze

  EVENT_TYPES = %w[lift_scan lesson rental].freeze
  DIFFICULTIES = %w[green blue black expert].freeze

  # operator name => [SQL symbol, the same comparison in Ruby]
  COUNT_OPERATORS = {
    "eq" => [ "=", :== ], "neq" => [ "!=", :!= ],
    "gt" => [ ">", :> ], "gte" => [ ">=", :>= ],
    "lt" => [ "<", :< ], "lte" => [ "<=", :<= ]
  }.freeze

  LAST_EVENT_OPERATORS = %w[older_than within].freeze

  MAX_RULES = 20
  MAX_DAYS = 3650
  MAX_COUNT = 1_000_000

  # The data covers the 2025-26 season, so "today" for rules like "not visited
  # in 30 days" is the last day of that season, not the real date.
  def self.as_of
    Date.parse(ENV.fetch("SEGMENT_AS_OF", "2026-04-12"))
  end
end
