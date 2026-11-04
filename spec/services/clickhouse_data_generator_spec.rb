require "rails_helper"

# Generates a small dataset once, then checks it is shaped the way we intend.
RSpec.describe ClickhouseDataGenerator do
  let(:client) { ClickhouseClient.new }

  before(:all) do
    @counts = described_class.new.generate!(guests: 2_000, events: 140_000)
  end

  def value(sql, params = {})
    client.query(sql, params).first.values.first
  end

  it "stores exactly the requested number of rows" do
    expect(@counts).to eq(guests: 2_000, events: 140_000)
  end

  it "produces the same data every time" do
    checksum = "SELECT sum(cityHash64(guest_id, event_time, event_type, lift_id, difficulty)) FROM events"
    first = value(checksum)

    described_class.new.generate!(guests: 2_000, events: 140_000)

    expect(value(checksum)).to eq(first)
  end

  it "only creates events for guests that exist" do
    expect(value("SELECT count() FROM events WHERE guest_id NOT IN (SELECT guest_id FROM guests)")).to eq(0)
  end

  it "keeps every event inside the 2025-26 season" do
    expect(value("SELECT toString(min(toDate(event_time))) FROM events")).to be >= "2025-11-27"
    expect(value("SELECT toString(max(toDate(event_time))) FROM events")).to be <= "2026-04-12"
  end

  it "gives a difficulty and a lift to lift scans only" do
    expect(value("SELECT count() FROM events WHERE event_type = 'lift_scan' AND (difficulty = '' OR lift_id = 0)")).to eq(0)
    expect(value("SELECT count() FROM events WHERE event_type != 'lift_scan' AND (difficulty != '' OR lift_id != 0)")).to eq(0)
  end

  it "has season pass holders visiting far more often than day pass guests" do
    events_per_guest = lambda do |pass|
      value(<<~SQL, pass: pass)
        SELECT count() / (SELECT count() FROM guests WHERE pass_type = {pass:String})
        FROM events WHERE guest_id IN (SELECT guest_id FROM guests WHERE pass_type = {pass:String})
      SQL
    end

    expect(events_per_guest.call("season")).to be > 5 * events_per_guest.call("day")
  end

  it "is busier on Saturdays than on Wednesdays" do
    per_day = ->(weekday) { value("SELECT avg(n) FROM (SELECT count() AS n FROM events WHERE toDayOfWeek(event_time) = {weekday:UInt8} GROUP BY toDate(event_time))", weekday: weekday) }

    expect(per_day.call(6)).to be > 1.5 * per_day.call(3)
  end

  it "has experts riding expert runs far more than beginners" do
    share = lambda do |skill|
      value(<<~SQL, skill: skill)
        SELECT countIf(difficulty = 'expert') / count() FROM events
        WHERE event_type = 'lift_scan' AND guest_id IN (SELECT guest_id FROM guests WHERE skill_level = {skill:String})
      SQL
    end

    expect(share.call("expert")).to be > 0.3
    expect(share.call("beginner")).to eq(0)
  end
end
