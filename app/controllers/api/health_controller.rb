module Api
  class HealthController < ApplicationController
    # GET /api/health
    def show
      render json: { status: "ok" }
    end
  end
end
