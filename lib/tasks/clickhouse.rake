# Commands for setting up ClickHouse. Run them from the project folder:
#
#   bin/rails clickhouse:migrate               create or update the tables
#   bin/rails clickhouse:generate              fill them with small data (100k events)
#   SCALE=full bin/rails clickhouse:generate   fill them with full data (10M events)
#   bin/rails clickhouse:stats                 print counts and distributions
namespace :clickhouse do
  desc "Create or update ClickHouse tables from db/clickhouse/migrate"
  task migrate: :environment do
    applied = ClickhouseMigrator.new.migrate!
    puts applied.empty? ? "Already up to date." : "Applied: #{applied.join(', ')}"
  end

  desc "Replace all guests and events with synthetic data (SCALE=small or full)"
  task generate: :migrate do
    scale = ENV.fetch("SCALE", "small")
    size = ClickhouseDataGenerator::SCALES.fetch(scale) do
      abort "Unknown SCALE=#{scale}. Use: #{ClickhouseDataGenerator::SCALES.keys.join(', ')}"
    end

    puts "Generating #{scale} data: #{size[:guests]} guests, #{size[:events]} events..."
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    counts = ClickhouseDataGenerator.new.generate!(**size)
    seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    puts "Stored #{counts[:guests]} guests and #{counts[:events]} events in #{seconds.round(1)}s."
  end

  desc "Print row counts and distributions to sanity-check the generated data"
  task stats: :environment do
    client = ClickhouseClient.new
    report = lambda do |title, sql|
      puts "\n== #{title}"
      client.query(sql).each { |row| puts "  " + row.values.join("  |  ") }
    end

    report.call "Row counts (guests | events)",
                "SELECT (SELECT count() FROM guests), (SELECT count() FROM events)"
    report.call "Guests by pass type (pass | guests | share %)", <<~SQL
      SELECT pass_type, count(), round(100 * count() / (SELECT count() FROM guests), 1)
      FROM guests GROUP BY pass_type ORDER BY count() DESC
    SQL
    report.call "Visits per guest by pass type (pass | avg visit days)", <<~SQL
      SELECT g.pass_type, round(avg(days), 1)
      FROM guests AS g
      LEFT JOIN (SELECT guest_id, uniqExact(toDate(event_time)) AS days FROM events GROUP BY guest_id) AS v
        ON g.guest_id = v.guest_id
      GROUP BY g.pass_type ORDER BY 2 DESC
    SQL
    report.call "Average events per day, by weekday (1 = Monday)", <<~SQL
      SELECT toDayOfWeek(day) AS weekday, round(avg(n)) FROM
        (SELECT toDate(event_time) AS day, count() AS n FROM events GROUP BY day)
      GROUP BY weekday ORDER BY weekday
    SQL
    report.call "Busiest days (date | events)", <<~SQL
      SELECT toDate(event_time) AS day, count() FROM events GROUP BY day ORDER BY count() DESC LIMIT 5
    SQL
    report.call "Lift scan difficulty by skill (skill | green % | blue % | black % | expert %)", <<~SQL
      SELECT g.skill_level,
             round(100 * countIf(e.difficulty = 'green') / count(), 1),
             round(100 * countIf(e.difficulty = 'blue') / count(), 1),
             round(100 * countIf(e.difficulty = 'black') / count(), 1),
             round(100 * countIf(e.difficulty = 'expert') / count(), 1)
      FROM events AS e INNER JOIN guests AS g ON e.guest_id = g.guest_id
      WHERE e.event_type = 'lift_scan'
      GROUP BY g.skill_level
      ORDER BY indexOf(['beginner', 'intermediate', 'advanced', 'expert'], g.skill_level)
    SQL
    report.call "Event types (type | events | share %)", <<~SQL
      SELECT event_type, count(), round(100 * count() / (SELECT count() FROM events), 2)
      FROM events GROUP BY event_type ORDER BY count() DESC
    SQL
  end
end
