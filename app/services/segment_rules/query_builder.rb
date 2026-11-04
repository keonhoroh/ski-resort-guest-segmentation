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
  class QueryBuilder
    DATE_TIME = "DateTime('UTC')".freeze

    attr_reader :params

    def initialize(definition, as_of: SegmentRules.as_of)
      validator = Validator.new(definition)
      raise InvalidRules, validator.errors.join("; ") unless validator.valid?

      definition = definition.deep_stringify_keys
      @params = {}
      # Events count if they happened before the end of the as_of day.
      @end_day = as_of + 1
      @end_time = param(time_at(@end_day), DATE_TIME)

      conditions = definition["rules"].map { |rule| send("#{rule['type']}_condition", rule) }
      @where = conditions.map { |condition| "(#{condition})" }
                         .join("\n  #{MATCHES.fetch(definition['match'])} ")
    end

    def count_sql
      "SELECT count() AS count FROM guests\nWHERE #{@where}"
    end

    def guest_ids_sql
      "SELECT guest_id FROM guests\nWHERE #{@where}\nORDER BY guest_id"
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
      filters = [ "event_type = #{param(rule['event'], 'String')}", "event_time < #{@end_time}" ]
      filters << "difficulty = #{param(rule['difficulty'], 'String')}" if rule["difficulty"]
      if rule["window_days"]
        filters << "event_time >= #{param(time_at(@end_day - rule['window_days']), DATE_TIME)}"
      end

      sql_operator, ruby_operator = COUNT_OPERATORS.fetch(rule["operator"])
      comparison = "count() #{sql_operator} #{param(rule['value'], 'UInt32')}"
      subquery = "SELECT guest_id FROM events WHERE #{filters.join(' AND ')} GROUP BY guest_id"

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
      cutoff = param(time_at(@end_day - rule["days"]), DATE_TIME)
      operator = rule["operator"] == "older_than" ? "<" : ">="

      "guest_id IN (SELECT guest_id FROM events WHERE event_time < #{@end_time} " \
        "GROUP BY guest_id HAVING max(event_time) #{operator} #{cutoff})"
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

    def time_at(date)
      date.strftime("%Y-%m-%d 00:00:00")
    end
  end
end
