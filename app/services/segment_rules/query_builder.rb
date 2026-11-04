module SegmentRules
  # Turns a segment definition into ClickHouse SQL plus a separate hash of values.
  #
  # The SQL text only ever contains column names and operators taken from our
  # own allow-lists. Every value the user typed goes into `params` and appears in
  # the SQL as a placeholder like {p0:String}.
  #
  #   builder = SegmentRules::QueryBuilder.new(definition)
  #   builder.count_sql  # => "SELECT count() AS count FROM guests WHERE (pass_type = {p0:String}) ..."
  #   builder.params     # => { "p0" => "season", ... }
  #   ClickhouseClient.new.query(builder.count_sql, builder.params)
  #
  # With email_opt_in_only: true, only guests who agreed to email are matched
  # (used when sending a campaign).
  #
  # `source` picks which table the event rules read:
  #   daily_event_counts  the daily summary (default, and the fastest)
  #   events              the raw events
  #   events_baseline     a deliberately badly organized copy (benchmark only)
  # All three give the same answers, because every rule's time limits fall on
  # midnight, so whole days are never split.
  class QueryBuilder
    DATE_TIME = "DateTime('UTC')".freeze

    # For each source: its day/time column, that column's type, and how to count events.
    RAW_EVENTS = { time: "event_time", type: DATE_TIME, count: "count()" }.freeze
    SOURCES = {
      "daily_event_counts" => { time: "event_date", type: "Date", count: "sum(events)" },
      "events" => RAW_EVENTS,
      "events_baseline" => RAW_EVENTS
    }.freeze

    attr_reader :params

    def initialize(definition, as_of: SegmentRules.as_of, email_opt_in_only: false, source: "daily_event_counts")
      validator = Validator.new(definition)
      raise InvalidRules, validator.errors.join("; ") unless validator.valid?

      @source = source
      @time, @time_type, @count = SOURCES.fetch(source) { raise ArgumentError, "unknown source: #{source}" }
                                         .values_at(:time, :type, :count)

      definition = definition.deep_stringify_keys
      @params = {}
      # Events count if they happened before the end of the as_of day.
      @end_day = as_of + 1
      @end_time = start_of(@end_day)

      conditions = definition["rules"].map { |rule| send("#{rule['type']}_condition", rule) }
      @where = conditions.map { |condition| "(#{condition})" }
                         .join("\n  #{MATCHES.fetch(definition['match'])} ")
      @where = "(#{@where})\n  AND email_opt_in = 1" if email_opt_in_only
    end

    def count_sql
      "SELECT count() AS count FROM guests\nWHERE #{@where}"
    end

    def guest_ids_sql
      "SELECT guest_id FROM guests\nWHERE #{@where}\nORDER BY guest_id"
    end

    # One page of matching guest IDs, in order, starting after a given ID.
    # Pass the page position along with the rule values:
    #   client.query(builder.guest_ids_batch_sql, builder.params.merge(after_guest_id: 0, batch_size: 1000))
    def guest_ids_batch_sql
      "SELECT guest_id FROM guests\nWHERE (#{@where})\n  AND guest_id > {after_guest_id:UInt64}\n" \
        "ORDER BY guest_id\nLIMIT {batch_size:UInt32}"
    end

    private

    # pass_type = {p1:String}
    def attribute_condition(rule)
      # `assoc` returns the key stored in ATTRIBUTES, so the column name in the
      # SQL is our own string, never the user's.
      column, spec = ATTRIBUTES.assoc(rule["field"])
      values = Array(rule["value"]).map { |value| param(clickhouse_value(value), spec[:type]) }

      case rule["operator"]
      when "eq" then "#{column} = #{values.first}"
      when "neq" then "#{column} != #{values.first}"
      when "in" then "#{column} IN (#{values.join(', ')})"
      end
    end

    # Guests whose number of matching events passes the comparison.
    def event_count_condition(rule)
      filters = [ "event_type = #{param(rule['event'], 'String')}", "#{@time} < #{@end_time}" ]
      filters << "difficulty = #{param(rule['difficulty'], 'String')}" if rule["difficulty"]
      filters << "#{@time} >= #{start_of(@end_day - rule['window_days'])}" if rule["window_days"]

      sql_operator, ruby_operator = COUNT_OPERATORS.fetch(rule["operator"])
      comparison = "#{@count} #{sql_operator} #{param(rule['value'], 'UInt32')}"
      subquery = "SELECT guest_id FROM #{@source} WHERE #{filters.join(' AND ')} GROUP BY guest_id"

      # Guests with zero matching events never appear in the subquery. When zero
      # passes the comparison (for example "fewer than 3 lessons"), include them
      # by excluding everyone whose count fails it instead.
      if 0.public_send(ruby_operator, rule["value"])
        "guest_id NOT IN (#{subquery} HAVING NOT (#{comparison}))"
      else
        "guest_id IN (#{subquery} HAVING #{comparison})"
      end
    end

    # older_than: has visited, but not in the last N days (never-visited guests are excluded).
    # within:     visited at least once in the last N days.
    def last_event_condition(rule)
      cutoff = start_of(@end_day - rule["days"])
      operator = rule["operator"] == "older_than" ? "<" : ">="

      "guest_id IN (SELECT guest_id FROM #{@source} WHERE #{@time} < #{@end_time} " \
        "GROUP BY guest_id HAVING max(#{@time}) #{operator} #{cutoff})"
    end

    # Stores a value and returns its placeholder, such as {p3:String}.
    def param(value, type)
      name = "p#{@params.size}"
      @params[name] = value
      "{#{name}:#{type}}"
    end

    def clickhouse_value(value)
      { true => 1, false => 0 }.fetch(value, value)
    end

    # A placeholder for the very start (midnight) of a day, in the source's
    # own type: a Date for the summary, a DateTime for raw events.
    def start_of(date)
      value = @time_type == "Date" ? date.iso8601 : date.strftime("%Y-%m-%d 00:00:00")
      param(value, @time_type)
    end
  end
end
