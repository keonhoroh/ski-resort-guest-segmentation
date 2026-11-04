require "net/http"
require "json"

# Sends SQL to ClickHouse over its HTTP interface.
#
# Values are NEVER pasted into the SQL text. The SQL uses placeholders like
# {name:Type}, and each value travels separately as a "param_name" setting.
# ClickHouse fills the placeholders itself and treats values strictly as data.
#
#   client = ClickhouseClient.new
#   client.query("SELECT {n:UInt32} + 1 AS answer", n: 41)   # => [{ "answer" => 42 }]
#   client.execute("TRUNCATE TABLE events")                   # no rows back
#   client.insert_rows("guests", [{ guest_id: 1, ... }])
class ClickhouseClient
  # Raised when ClickHouse rejects a query or can't be reached.
  class Error < StandardError; end

  TABLE_NAME = /\A[a-z_][a-z0-9_]*\z/

  attr_reader :database

  def initialize(
    url: ENV.fetch("CLICKHOUSE_URL"),
    user: ENV.fetch("CLICKHOUSE_USER"),
    password: ENV.fetch("CLICKHOUSE_PASSWORD"),
    database: ENV.fetch("CLICKHOUSE_DB")
  )
    @uri = URI(url)
    @user = user
    @password = password
    @database = database
  end

  # Runs a SELECT and returns its rows as an array of hashes.
  def query(sql, params = {})
    body = post(sql, params, default_format: "JSON",
                             # Return big integers (like counts) as numbers, not strings.
                             output_format_json_quote_64bit_integers: 0)
    JSON.parse(body).fetch("data")
  end

  # Runs a statement that returns no rows (CREATE, INSERT ... SELECT, TRUNCATE).
  def execute(sql, params = {})
    post(sql, params)
    nil
  end

  # Inserts an array of hashes into a table, one hash per row.
  def insert_rows(table, rows)
    raise ArgumentError, "invalid table name: #{table.inspect}" unless table.to_s.match?(TABLE_NAME)
    return if rows.empty?

    # For inserts, the SQL goes in the URL and the rows go in the body.
    post(rows.map(&:to_json).join("\n"), {}, query: "INSERT INTO #{table} FORMAT JSONEachRow")
    nil
  end

  private

  def post(body, params, extra_settings = {})
    settings = { database: @database }.merge(extra_settings)
    params.each { |name, value| settings["param_#{name}"] = value }

    uri = @uri.dup
    uri.query = URI.encode_www_form(settings)

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(@user, @password)
    request.body = body

    response = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 2, read_timeout: 300) do |http|
      http.request(request)
    end

    raise Error, response.body.to_s.strip unless response.is_a?(Net::HTTPSuccess)

    response.body
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Could not reach ClickHouse: #{e.message}"
  end
end
