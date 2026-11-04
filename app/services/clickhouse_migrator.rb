# Applies the numbered SQL files in db/clickhouse/migrate/ in order, once each.
# Applied versions are recorded in a clickhouse_migrations table, so running
# it again only applies new files.
#
# A file may hold several statements; each must end with ; at the end of a line.
class ClickhouseMigrator
  MIGRATIONS_DIR = Rails.root.join("db/clickhouse/migrate")

  def initialize(client: ClickhouseClient.new)
    @client = client
  end

  # Returns the versions applied by this run, e.g. ["001", "002"].
  def migrate!
    create_database
    create_migrations_table

    applied = @client.query("SELECT version FROM clickhouse_migrations").map { |row| row["version"] }

    pending_files(applied).map do |path|
      version = File.basename(path).split("_").first
      statements(path).each { |sql| @client.execute(sql) }
      @client.insert_rows("clickhouse_migrations", [ { version: version } ])
      version
    end
  end

  private

  def create_database
    # The target database may not exist yet, so connect to "default" to create it.
    admin = ClickhouseClient.new(database: "default")
    admin.execute("CREATE DATABASE IF NOT EXISTS {db:Identifier}", db: @client.database)
  end

  def create_migrations_table
    @client.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS clickhouse_migrations
      (
          version    String,
          applied_at DateTime('UTC') DEFAULT now()
      )
      ENGINE = MergeTree
      ORDER BY version
    SQL
  end

  def pending_files(applied)
    Dir[MIGRATIONS_DIR.join("*.sql")].sort.reject do |path|
      applied.include?(File.basename(path).split("_").first)
    end
  end

  def statements(path)
    File.read(path).split(/;\s*$/).map(&:strip).reject(&:empty?)
  end
end
