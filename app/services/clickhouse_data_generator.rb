# Replaces all guests and events with freshly generated synthetic data.
# The SQL in db/clickhouse/generate/ runs inside ClickHouse, which is far
# faster than sending millions of rows from Ruby.
#
#   ClickhouseDataGenerator.new.generate!(**ClickhouseDataGenerator::SCALES["small"])
class ClickhouseDataGenerator
  SCALES = {
    "small" => { guests: 1_000, events: 100_000 },
    "full" => { guests: 100_000, events: 10_000_000 }
  }.freeze

  SQL_DIR = Rails.root.join("db/clickhouse/generate")

  def initialize(client: ClickhouseClient.new)
    @client = client
  end

  # Returns the row counts actually stored, e.g. { guests: 1000, events: 100000 }.
  def generate!(guests:, events:)
    raise ArgumentError, "need at least 100 guests" if guests < 100

    @client.execute("TRUNCATE TABLE events")
    @client.execute("TRUNCATE TABLE guests")
    @client.execute(SQL_DIR.join("guests.sql").read, guests: guests)
    @client.execute(SQL_DIR.join("events.sql").read, events: events)

    {
      guests: @client.query("SELECT count() AS n FROM guests").first["n"],
      events: @client.query("SELECT count() AS n FROM events").first["n"]
    }
  end
end
