require "rails_helper"

RSpec.describe SegmentRules::Validator do
  def errors_for(definition)
    validator = described_class.new(definition)
    validator.valid?
    validator.errors
  end

  def one_rule(rule)
    { "match" => "all", "rules" => [ rule ] }
  end

  it "accepts the three example segments" do
    ClickhouseFixtures::SEGMENTS.each_value do |definition|
      expect(errors_for(definition)).to eq([])
    end
  end

  it "accepts symbol keys" do
    expect(errors_for(match: "any", rules: [ { type: "last_event", operator: "within", days: 7 } ])).to eq([])
  end

  it "accepts an in list" do
    rule = { "type" => "attribute", "field" => "skill_level", "operator" => "in", "value" => %w[advanced expert] }
    expect(errors_for(one_rule(rule))).to eq([])
  end

  {
    "a non-object" => [ "rules", /must be an object/ ],
    "a bad match" => [ { "match" => "some", "rules" => [ { "type" => "last_event", "operator" => "within", "days" => 1 } ] }, /match must be/ ],
    "no rules" => [ { "match" => "all", "rules" => [] }, /list of 1 to 20/ ],
    "too many rules" => [ { "match" => "all", "rules" => Array.new(21) { { "type" => "last_event", "operator" => "within", "days" => 1 } } }, /list of 1 to 20/ ],
    "an extra top-level key" => [ { "match" => "all", "rules" => [ { "type" => "last_event", "operator" => "within", "days" => 1 } ], "limit" => 5 }, /unknown keys: limit/ ]
  }.each do |description, (definition, message)|
    it "rejects #{description}" do
      expect(errors_for(definition)).to include(message)
    end
  end

  {
    "an unknown rule type" => [ { "type" => "purchase" }, /type must be one of/ ],
    "an unknown field" => [ { "type" => "attribute", "field" => "email", "operator" => "eq", "value" => "x" }, /field must be one of/ ],
    "an unknown attribute operator" => [ { "type" => "attribute", "field" => "pass_type", "operator" => "like", "value" => "season" }, /operator must be one of/ ],
    "an unknown attribute value" => [ { "type" => "attribute", "field" => "pass_type", "operator" => "eq", "value" => "gold" }, /value for pass_type must be one of/ ],
    "an empty in list" => [ { "type" => "attribute", "field" => "pass_type", "operator" => "in", "value" => [] }, /non-empty list/ ],
    "an unknown event type" => [ { "type" => "event_count", "event" => "purchase", "operator" => "gte", "value" => 1 }, /event must be one of/ ],
    "difficulty on a lesson" => [ { "type" => "event_count", "event" => "lesson", "difficulty" => "black", "operator" => "gte", "value" => 1 }, /difficulty only applies/ ],
    "an unknown difficulty" => [ { "type" => "event_count", "event" => "lift_scan", "difficulty" => "double_black", "operator" => "gte", "value" => 1 }, /difficulty must be one of/ ],
    "a count given as text" => [ { "type" => "event_count", "event" => "lesson", "operator" => "gte", "value" => "50" }, /value must be a whole number/ ],
    "a negative count" => [ { "type" => "event_count", "event" => "lesson", "operator" => "gte", "value" => -1 }, /value must be a whole number/ ],
    "a zero-day window" => [ { "type" => "event_count", "event" => "lesson", "operator" => "gte", "value" => 1, "window_days" => 0 }, /window_days must be/ ],
    "an unknown last_event operator" => [ { "type" => "last_event", "operator" => "before", "days" => 30 }, /operator must be one of/ ],
    "missing days" => [ { "type" => "last_event", "operator" => "older_than" }, /days must be/ ],
    "an extra rule key" => [ { "type" => "last_event", "operator" => "within", "days" => 3, "sql" => "1=1" }, /unknown keys: sql/ ]
  }.each do |description, (rule, message)|
    it "rejects #{description}" do
      expect(errors_for(one_rule(rule))).to include(message)
    end
  end

  describe "attempted SQL injection" do
    it "rejects SQL in a field name" do
      rule = { "type" => "attribute", "field" => "pass_type = 'season' OR 1=1 --", "operator" => "eq", "value" => "season" }
      expect(errors_for(one_rule(rule))).to include(/field must be one of/)
    end

    it "rejects SQL in an operator" do
      rule = { "type" => "event_count", "event" => "lesson", "operator" => ">= 0 OR 1=1", "value" => 1 }
      expect(errors_for(one_rule(rule))).to include(/operator must be one of/)
    end

    it "rejects SQL in a value" do
      rule = { "type" => "attribute", "field" => "pass_type", "operator" => "eq", "value" => "season' OR '1'='1" }
      expect(errors_for(one_rule(rule))).to include(/value for pass_type must be one of/)
    end
  end
end
