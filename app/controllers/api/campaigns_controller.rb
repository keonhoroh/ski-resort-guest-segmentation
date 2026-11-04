module Api
  class CampaignsController < ApplicationController
    rescue_from ActiveRecord::RecordNotFound, with: :not_found

    # GET /api/campaigns   Newest first.
    def index
      campaigns = Campaign.includes(:segment).order(created_at: :desc).limit(50)
      render json: campaigns.map { |campaign| campaign_json(campaign) }
    end

    # GET /api/campaigns/:id   The web page asks this every second for progress.
    def show
      render json: campaign_json(Campaign.find(params[:id]))
    end

    # POST /api/segments/:segment_id/campaigns   Body: { "name": "...", "message": "..." }
    # Saves the campaign, then hands the sending to a background job.
    def create
      segment = Segment.find(params[:segment_id])
      campaign = segment.campaigns.new(request.request_parameters.slice("name", "message"))
      campaign.rules = segment.rules

      unless campaign.save
        return render json: { errors: campaign.errors.full_messages }, status: :unprocessable_content
      end

      SendCampaignJob.perform_later(campaign.id)
      render json: campaign_json(campaign), status: :created
    end

    private

    def campaign_json(campaign)
      campaign.as_json(only: %i[id segment_id name message status audience_count sent_count
                                started_at finished_at created_at])
              .merge("segment_name" => campaign.segment.name)
    end

    def not_found
      render json: { error: "Not found" }, status: :not_found
    end
  end
end
