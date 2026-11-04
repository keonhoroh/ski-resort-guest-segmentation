# Performance measurements. Run them against the full 10M-event data:
#
#   bin/rails bench:baseline   build events_baseline, a deliberately badly organized copy of events
#   bin/rails bench:segments   time the example segments against each source table
#                              (SOURCE=daily_event_counts, events, events_baseline, or all)
namespace :bench do
  desc "Copy events into events_baseline: no sort key, no monthly partitions, rows shuffled"
  task baseline: :environment do
    client = ClickhouseClient.new
    client.execute("DROP TABLE IF EXISTS events_baseline")
    # Same columns as events, but no PARTITION BY and no sort key.
    # (CREATE TABLE ... AS events would copy the partitioning too.)
    client.execute(<<~SQL)
      CREATE TABLE events_baseline
      (
          event_time DateTime('UTC'),
          guest_id   UInt64,
          event_type LowCardinality(String),
          lift_id    UInt16,
          difficulty LowCardinality(String)
      )
      ENGINE = MergeTree
      ORDER BY tuple()
    SQL
    client.execute("INSERT INTO events_baseline SELECT * FROM events ORDER BY rand()")
    # Merge into as few parts as possible, like the main table after its own merges.
    client.execute("OPTIMIZE TABLE events_baseline FINAL")
    rows = client.query("SELECT count() AS n FROM events_baseline").first["n"]
    puts "events_baseline has #{rows} rows."
  end

  desc "Time the example segments: median of 5 runs, plus rows and bytes read"
  task segments: :environment do
    client = ClickhouseClient.new
    sources = SegmentRules::QueryBuilder::SOURCES.keys.reverse # worst first
    sources = [ ENV["SOURCE"] ] unless ENV.fetch("SOURCE", "all") == "all"
    events = client.query("SELECT count() AS n FROM events").first["n"]
    puts "events: #{events} rows. Median of #{SegmentBenchmark::RUNS} runs after one warm-up.\n\n"

    puts "| Source | Segment | Guests | Median ms | Rows read | Data read |"
    puts "|---|---|---:|---:|---:|---:|"
    sources.each do |source|
      SegmentBenchmark.new(source: source, client: client).run.each do |r|
        puts "| `#{source}` | #{r[:name]} | #{r[:guests]} | #{r[:median_ms]} | " \
             "#{r[:rows_read].to_i.to_fs(:delimited)} | #{r[:bytes_read].to_i.to_fs(:human_size)} |"
      end
    end
  end
end
