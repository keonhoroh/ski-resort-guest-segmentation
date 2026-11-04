module Api
  class SegmentsController < ApplicationController
    # POST /api/segments/preview
    # Body: { "rules": { "match": "all", "rules": [...] } }
    # Returns how many guests match, and how long the query took.
    def preview
      rules = request.request_parameters["rules"]
      validator = SegmentRules::Validator.new(rules)
      return render json: { errors: validator.errors }, status: :unprocessable_content unless validator.valid?

      builder = SegmentRules::QueryBuilder.new(rules)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      count = ClickhouseClient.new.query(builder.count_sql, builder.params).first.fetch("count")
      query_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000

      render json: { count: count, query_ms: query_ms.round(1) }
    rescue ClickhouseClient::Error => e
      Rails.logger.error("Segment preview failed: #{e.message}")
      render json: { error: "The segment query failed" }, status: :service_unavailable
    end
  end
end
