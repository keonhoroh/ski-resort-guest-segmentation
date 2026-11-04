require "rails_helper"

RSpec.describe "Campaigns API", type: :request do
  include ActiveJob::TestHelper

  let(:lapsed) { ClickhouseFixtures::SEGMENTS[:season_lapsed_30_days] }
  let(:segment) { Segment.create!(name: "Lapsed season pass", rules: lapsed) }

  before do
    ClickhouseFixtures.load!
    allow(SegmentRules).to receive(:as_of).and_return(ClickhouseFixtures::AS_OF)
  end

  def json
    response.parsed_body
  end

  def launch(body)
    post "/api/segments/#{segment.id}/campaigns", params: body, as: :json
  end

  describe "POST /api/segments/:segment_id/campaigns" do
    it "saves a queued campaign and enqueues the job" do
      expect { launch(name: "Come back", message: "We miss you") }
        .to have_enqueued_job(SendCampaignJob).with(kind_of(Integer))

      expect(response).to have_http_status(:created)
      expect(json).to include("name" => "Come back", "status" => "queued", "sent_count" => 0,
                              "segment_name" => "Lapsed season pass")
      expect(Campaign.find(json["id"]).rules).to eq(lapsed)
    end

    it "sends to opted-in guests once the job runs" do
      perform_enqueued_jobs { launch(name: "Come back", message: "We miss you") }

      get "/api/campaigns/#{json['id']}"
      # Guests 2 and 3 are lapsed season pass holders, but guest 3 opted out of email.
      expect(json).to include("status" => "completed", "audience_count" => 1, "sent_count" => 1)
    end

    it "rejects a campaign without a name or message" do
      expect { launch(name: "", message: "") }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to include("Name can't be blank", "Message can't be blank")
    end

    it "ignores fields the request should not set" do
      launch(name: "Sneaky", message: "Hi", status: "completed", sent_count: 999)

      expect(json).to include("status" => "queued", "sent_count" => 0)
    end

    it "returns 404 for a missing segment" do
      post "/api/segments/0/campaigns", params: { name: "x", message: "y" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/campaigns" do
    it "lists campaigns newest first" do
      old = segment.campaigns.create!(name: "Old", message: "m", rules: lapsed, created_at: 1.day.ago)
      new = segment.campaigns.create!(name: "New", message: "m", rules: lapsed)

      get "/api/campaigns"

      expect(json.map { |c| c["id"] }).to eq([ new.id, old.id ])
    end
  end

  describe "GET /api/campaigns/:id" do
    it "returns 404 for a missing campaign" do
      get "/api/campaigns/0"
      expect(response).to have_http_status(:not_found)
    end
  end
end
