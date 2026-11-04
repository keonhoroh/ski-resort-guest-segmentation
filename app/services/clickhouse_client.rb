require "net/http"
require "json"

# Sends SQL to ClickHouse over its HTTP interface and returns the rows.
#
# Values are NEVER pasted into the SQL text. The SQL uses placeholders like
# {name:Type}, and each value travels separately as a "param_name" setting.
# ClickHouse fills the placeholders itself and treats values strictly as data.
#
#   ClickhouseClient.new.query("SELECT {n:UInt32} + 1 AS answer", n: 41)
#   # => [{ "answer" => 42 }]
class ClickhouseClient
  # Raised when ClickHouse rejects a query or can't be reached.
  class Error < StandardError; end

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

  # Runs one SQL statement and returns its rows as an array of hashes.
  def query(sql, params = {})
    settings = { database: @database, default_format: "JSON" }
    params.each { |name, value| settings["param_#{name}"] = value }

    uri = @uri.dup
    uri.query = URI.encode_www_form(settings)

    request = Net::HTTP::Post.new(uri)
    request.basic_auth(@user, @password)
    request.body = sql

    response = Net::HTTP.start(uri.host, uri.port,
                               use_ssl: uri.scheme == "https",
                               open_timeout: 2, read_timeout: 30) do |http|
      http.request(request)
    end

    raise Error, response.body.to_s.strip unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("data")
  rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout => e
    raise Error, "Could not reach ClickHouse: #{e.message}"
  end
end
