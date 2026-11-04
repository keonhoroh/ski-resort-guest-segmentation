module Api
  # GET /api/health
  # Asks each database a trivial question and reports which ones answered.
  class HealthController < ApplicationController
    def show
      services = {
        postgres: check { ActiveRecord::Base.connection.select_value("SELECT 1") },
        clickhouse: check { ClickhouseClient.new.query("SELECT 1") },
        redis: check { Sidekiq.redis { |conn| conn.call("PING") } }
      }

      healthy = services.values.all?("ok")

      render json: { status: healthy ? "ok" : "degraded", services: services },
             status: healthy ? :ok : :service_unavailable
    end

    private

    # Runs one check. Returns "ok" or "error". The details go to the server
    # log, not the response, so we don't expose internals publicly.
    def check
      yield
      "ok"
    rescue StandardError => e
      Rails.logger.warn("Health check failed: #{e.class}: #{e.message}")
      "error"
    end
  end
end
