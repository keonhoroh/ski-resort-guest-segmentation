require "securerandom"

# Times the three example segments against ClickHouse and reads back what each
# query cost from ClickHouse's own log (system.query_log).
#
#   SegmentBenchmark.new(source: "events").run
#   # => [{ name: "Season pass, lapsed 30 days", guests: 62, median_ms: 41, rows_read: ..., bytes_read: ... }, ...]
class SegmentBenchmark
  SEGMENTS = {
    "Season pass, lapsed 30 days" => {
      "match" => "all",
      "rules" => [
        { "type" => "attribute", "field" => "pass_type", "operator" => "eq", "value" => "season" },
        { "type" => "last_event", "operator" => "older_than", "days" => 30 }
      ]
    },
    "50+ expert scans in 120 days" => {
      "match" => "all",
      "rules" => [
        { "type" => "event_count", "event" => "lift_scan", "difficulty" => "expert",
          "operator" => "gte", "value" => 50, "window_days" => 120 }
      ]
    },
    "Lesson, no visit in 14 days" => {
      "match" => "all",
      "rules" => [
        { "type" => "event_count", "event" => "lesson", "operator" => "gte", "value" => 1 },
        { "type" => "last_event", "operator" => "older_than", "days" => 14 }
      ]
    }
  }.freeze

  RUNS = 5

  def initialize(source:, client: ClickhouseClient.new)
    @source = source
    @client = client
  end

  def run
    SEGMENTS.map do |name, definition|
      builder = SegmentRules::QueryBuilder.new(definition, source: @source)

      # One warm-up run first, so every measured run starts with the data
      # already in memory. Then RUNS measured runs, each tagged with an ID.
      guests = @client.query(builder.count_sql, builder.params).first.fetch("count")
      query_ids = Array.new(RUNS) do
        id = "bench-#{SecureRandom.hex(8)}"
        @client.query(builder.count_sql, builder.params, { query_id: id })
        id
      end

      stats = logged_stats(query_ids)
      { name: name, guests: guests,
        median_ms: median(stats.map { |s| s["query_duration_ms"] }),
        rows_read: median(stats.map { |s| s["read_rows"] }),
        bytes_read: median(stats.map { |s| s["read_bytes"] }) }
    end
  end

  private

  def logged_stats(query_ids)
    # The log is written in the background; flush it so our queries are in it.
    @client.execute("SYSTEM FLUSH LOGS")
    # ClickHouse reads an Array parameter written like ['a','b']. The IDs are
    # our own random hex, so they need no escaping.
    ids = "[#{query_ids.map { |id| "'#{id}'" }.join(',')}]"
    @client.query(<<~SQL, ids: ids)
      SELECT query_duration_ms, read_rows, read_bytes
      FROM system.query_log
      WHERE type = 'QueryFinish' AND query_id IN {ids:Array(String)}
    SQL
  end

  def median(values)
    sorted = values.sort
    mid = sorted.size / 2
    sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
  end
end
