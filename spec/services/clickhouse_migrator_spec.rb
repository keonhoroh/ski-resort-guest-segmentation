require "rails_helper"

RSpec.describe ClickhouseMigrator do
  let(:client) { ClickhouseClient.new }

  it "creates the guests and events tables" do
    described_class.new.migrate!

    tables = client.query("SELECT name FROM system.tables WHERE database = {db:String}", db: client.database)
                   .map { |row| row["name"] }
    expect(tables).to include("guests", "events", "clickhouse_migrations")
  end

  it "does nothing when run again" do
    described_class.new.migrate!

    expect(described_class.new.migrate!).to eq([])
  end

  it "records every migration file as applied" do
    described_class.new.migrate!

    versions = client.query("SELECT version FROM clickhouse_migrations ORDER BY version").map { |row| row["version"] }
    files = Dir[ClickhouseMigrator::MIGRATIONS_DIR.join("*.sql")].map { |path| File.basename(path).split("_").first }
    expect(versions).to eq(files.sort)
  end
end
