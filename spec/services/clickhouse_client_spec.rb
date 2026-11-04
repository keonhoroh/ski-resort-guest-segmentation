require "rails_helper"

# These tests talk to the real ClickHouse running in Docker.
RSpec.describe ClickhouseClient do
  subject(:client) { described_class.new }

  it "runs a query and returns rows as hashes" do
    rows = client.query("SELECT 1 AS one")

    expect(rows).to eq([ { "one" => 1 } ])
  end

  it "fills placeholders with values sent separately from the SQL" do
    rows = client.query("SELECT {n:UInt32} + 1 AS answer", n: 41)

    expect(rows).to eq([ { "answer" => 42 } ])
  end

  it "treats a sneaky value as plain text, not as SQL" do
    sneaky = "season'; DROP TABLE guests; --"

    rows = client.query("SELECT {value:String} AS value", value: sneaky)

    # The value comes back unchanged: ClickHouse never ran it as a command.
    expect(rows).to eq([ { "value" => sneaky } ])
  end

  it "raises a ClickhouseClient::Error when the SQL is invalid" do
    expect { client.query("SELEKT nonsense") }
      .to raise_error(ClickhouseClient::Error, /Syntax error/)
  end

  it "raises a ClickhouseClient::Error when ClickHouse can't be reached" do
    unreachable = described_class.new(url: "http://localhost:1")

    expect { unreachable.query("SELECT 1") }
      .to raise_error(ClickhouseClient::Error, /Could not reach ClickHouse/)
  end
end
