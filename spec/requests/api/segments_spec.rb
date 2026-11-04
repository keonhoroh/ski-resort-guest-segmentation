require "rails_helper"

RSpec.describe "Segments API", type: :request do
  let(:lapsed) { ClickhouseFixtures::SEGMENTS[:season_lapsed_30_days] }
  let(:experts) { ClickhouseFixtures::SEGMENTS[:expert_scans_50_in_120_days] }
  let(:bad_rules) { { "match" => "all", "rules" => [ { "type" => "attribute", "field" => "password", "operator" => "eq", "value" => "x" } ] } }

  before do
    ClickhouseFixtures.load!
    allow(SegmentRules).to receive(:as_of).and_return(ClickhouseFixtures::AS_OF)
  end

  def json
    response.parsed_body
  end

  def stub_clickhouse_failure
    failing = instance_double(ClickhouseClient)
    allow(failing).to receive(:query).and_raise(ClickhouseClient::Error, "boom")
    allow(ClickhouseClient).to receive(:new).and_return(failing)
  end

  describe "POST /api/segments/preview" do
    def preview(rules)
      post "/api/segments/preview", params: { rules: rules }, as: :json
    end

    it "returns the audience count and query time" do
      preview(lapsed)

      expect(response).to have_http_status(:ok)
      expect(json["count"]).to eq(2)
      expect(json["query_ms"]).to be_a(Numeric)
    end

    it "returns 422 with the problems when rules are invalid" do
      preview(bad_rules)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to include(/field must be one of/)
    end

    it "returns 422 when rules are missing" do
      post "/api/segments/preview", params: {}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects an attempted SQL injection" do
      preview({ match: "all", rules: [ { type: "attribute", field: "pass_type", operator: "eq",
                                         value: "season' OR 1=1; DROP TABLE guests; --" } ] })

      expect(response).to have_http_status(:unprocessable_content)
      expect(ClickhouseClient.new.query("SELECT count() AS n FROM guests").first["n"]).to eq(9)
    end

    it "returns 503 when ClickHouse fails" do
      stub_clickhouse_failure
      preview(lapsed)

      expect(response).to have_http_status(:service_unavailable)
      expect(json).to eq("error" => "The segment query failed")
    end
  end

  describe "GET /api/segments/options" do
    it "returns the allow-lists" do
      get "/api/segments/options"

      expect(json["attributes"]["pass_type"]).to eq(%w[season multi_day day])
      expect(json["count_operators"]).to include("gte")
      expect(json["max_rules"]).to eq(20)
    end
  end

  describe "POST /api/segments" do
    it "saves the segment with its current count" do
      post "/api/segments", params: { name: "Lapsed season pass", rules: lapsed }, as: :json

      expect(response).to have_http_status(:created)
      expect(json).to include("name" => "Lapsed season pass", "rules" => lapsed, "last_count" => 2)
      expect(Segment.count).to eq(1)
    end

    it "ignores keys that are not name or rules" do
      post "/api/segments", params: { name: "Experts", rules: experts, last_count: 999, id: 12345 }, as: :json

      expect(json["last_count"]).to eq(1)
      expect(json["id"]).not_to eq(12345)
    end

    it "returns 422 and saves nothing when the name is missing or rules are invalid" do
      post "/api/segments", params: { name: "", rules: bad_rules }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to include("Name can't be blank", /field must be one of/)
      expect(Segment.count).to eq(0)
    end

    it "returns 503 and saves nothing when ClickHouse fails" do
      stub_clickhouse_failure
      post "/api/segments", params: { name: "Lapsed", rules: lapsed }, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(Segment.count).to eq(0)
    end
  end

  describe "with a saved segment" do
    let!(:segment) { Segment.create!(name: "Lapsed season pass", rules: lapsed, last_count: 2) }

    it "lists segments, newest first" do
      older = Segment.create!(name: "Older", rules: experts, updated_at: 1.day.ago)
      get "/api/segments"

      expect(json.map { |s| s["id"] }).to eq([ segment.id, older.id ])
    end

    it "shows one segment" do
      get "/api/segments/#{segment.id}"

      expect(json).to include("id" => segment.id, "name" => "Lapsed season pass", "last_count" => 2)
    end

    it "returns 404 for a segment that does not exist" do
      get "/api/segments/0"

      expect(response).to have_http_status(:not_found)
    end

    it "updates the rules and recounts" do
      patch "/api/segments/#{segment.id}", params: { rules: experts }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json).to include("name" => "Lapsed season pass", "rules" => experts, "last_count" => 1)
    end

    it "does not change anything when an update is invalid" do
      patch "/api/segments/#{segment.id}", params: { rules: bad_rules }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(segment.reload.rules).to eq(lapsed)
    end

    it "deletes a segment" do
      delete "/api/segments/#{segment.id}"

      expect(response).to have_http_status(:no_content)
      expect(Segment.exists?(segment.id)).to be(false)
    end
  end
end
