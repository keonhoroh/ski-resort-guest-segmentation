require "rails_helper"

# Proves the fixture's EXPECTED answers with plain hand-written SQL, so the
# Stage 3 segment engine has a trustworthy target to match.
RSpec.describe ClickhouseFixtures do
  let(:client) { ClickhouseClient.new }
  # "Now" is the end of the AS_OF day.
  let(:now) { (ClickhouseFixtures::AS_OF + 1).strftime("%Y-%m-%d 00:00:00") }

  before { described_class.load!(client) }

  def guest_ids(sql)
    client.query(sql, now: now).map { |row| row["guest_id"] }
  end

  it "loads 9 guests and their events" do
    expect(client.query("SELECT count() AS n FROM guests").first["n"]).to eq(9)
    expect(client.query("SELECT count() AS n FROM events").first["n"]).to eq(described_class.events.size)
  end

  it "has the right season pass holders who have not visited in 30 days" do
    ids = guest_ids(<<~SQL)
      SELECT guest_id FROM guests
      WHERE pass_type = 'season'
        AND guest_id NOT IN (
          SELECT guest_id FROM events WHERE event_time >= {now:DateTime('UTC')} - INTERVAL 30 DAY)
      ORDER BY guest_id
    SQL

    expect(ids).to eq(described_class::EXPECTED[:season_lapsed_30_days])
  end

  it "has the right guests with 50+ expert lift scans in 120 days" do
    ids = guest_ids(<<~SQL)
      SELECT guest_id FROM events
      WHERE event_type = 'lift_scan' AND difficulty = 'expert'
        AND event_time >= {now:DateTime('UTC')} - INTERVAL 120 DAY
      GROUP BY guest_id
      HAVING count() >= 50
      ORDER BY guest_id
    SQL

    expect(ids).to eq(described_class::EXPECTED[:expert_scans_50_in_120_days])
  end

  it "has the right guests who took a lesson but have not returned in 14 days" do
    ids = guest_ids(<<~SQL)
      SELECT DISTINCT guest_id FROM events
      WHERE event_type = 'lesson'
        AND guest_id NOT IN (
          SELECT guest_id FROM events WHERE event_time >= {now:DateTime('UTC')} - INTERVAL 14 DAY)
      ORDER BY guest_id
    SQL

    expect(ids).to eq(described_class::EXPECTED[:lesson_not_returned_14_days])
  end
end
