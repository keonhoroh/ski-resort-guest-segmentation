module SegmentRules
  # Counts the guests matching a segment definition, and times the query.
  #
  #   SegmentRules::Counter.call(definition)  # => { count: 62, query_ms: 37.0 }
  class Counter
    def self.call(definition, client: ClickhouseClient.new)
      builder = QueryBuilder.new(definition)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      count = client.query(builder.count_sql, builder.params).first.fetch("count")
      query_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

      { count: count, query_ms: query_ms.round(1) }
    end
  end
end
