require "rails_helper"

# Runs real queries against the 9-guest fixture, where the right answers are known.
RSpec.describe SegmentRules::QueryBuilder do
  let(:client) { ClickhouseClient.new }

  before(:all) { ClickhouseFixtures.load! }

  def guest_ids(definition)
    builder = described_class.new(definition, as_of: ClickhouseFixtures::AS_OF)
    client.query(builder.guest_ids_sql, builder.params).map { |row| row["guest_id"] }
  end

  def count(definition)
    builder = described_class.new(definition, as_of: ClickhouseFixtures::AS_OF)
    client.query(builder.count_sql, builder.params).first["count"]
  end

  def rule(**fields)
    fields.transform_keys(&:to_s)
  end

  def segment(match, *rules)
    { "match" => match, "rules" => rules }
  end

  let(:season) { rule(type: "attribute", field: "pass_type", operator: "eq", value: "season") }
  let(:beginner) { rule(type: "attribute", field: "skill_level", operator: "eq", value: "beginner") }

  ClickhouseFixtures::SEGMENTS.each do |name, definition|
    it "finds the right guests for #{name}" do
      expect(guest_ids(definition)).to eq(ClickhouseFixtures::EXPECTED.fetch(name))
      expect(count(definition)).to eq(ClickhouseFixtures::EXPECTED.fetch(name).size)
    end
  end

  it "joins rules with AND when match is all" do
    expect(guest_ids(segment("all", season, beginner))).to eq([])
  end

  it "joins rules with OR when match is any" do
    expect(guest_ids(segment("any", season, beginner))).to eq([ 1, 2, 3, 4, 5, 7 ])
  end

  it "returns zero when nobody matches" do
    rentals = rule(type: "event_count", event: "rental", operator: "gte", value: 1)
    expect(count(segment("all", rentals))).to eq(0)
  end

  it "supports neq and in" do
    not_day = rule(type: "attribute", field: "pass_type", operator: "neq", value: "day")
    regions = rule(type: "attribute", field: "home_region", operator: "in", value: %w[Northeast Pacific])
    expect(guest_ids(segment("all", not_day, regions))).to eq([ 1, 3 ])
  end

  it "supports email_opt_in" do
    opted_out = rule(type: "attribute", field: "email_opt_in", operator: "eq", value: false)
    expect(guest_ids(segment("all", opted_out))).to eq([ 3 ])
  end

  it "includes guests with no events when zero passes the comparison" do
    no_lessons = rule(type: "event_count", event: "lesson", operator: "lt", value: 1)
    expect(guest_ids(segment("all", no_lessons))).to eq([ 1, 2, 3, 6, 7, 8, 9 ])
  end

  it "finds guests who visited within N days" do
    recent = rule(type: "last_event", operator: "within", days: 10)
    expect(guest_ids(segment("all", recent))).to eq([ 1, 5, 7 ])
  end

  it "leaves guests who never visited out of older_than" do
    lapsed = rule(type: "last_event", operator: "older_than", days: 30)
    expect(guest_ids(segment("all", lapsed))).to eq([ 2, 3, 6 ])
  end

  it "refuses rules that fail validation" do
    expect { described_class.new(segment("all", rule(type: "purchase"))) }
      .to raise_error(SegmentRules::InvalidRules, /type must be one of/)
  end

  it "keeps every value out of the SQL text" do
    definition = ClickhouseFixtures::SEGMENTS[:expert_scans_50_in_120_days]
    builder = described_class.new(definition, as_of: ClickhouseFixtures::AS_OF)

    expect(builder.count_sql).not_to include("lift_scan", "expert", "50")
    expect(builder.params.values).to include("lift_scan", "expert", 50)
  end
end
