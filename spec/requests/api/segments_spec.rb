require "rails_helper"

RSpec.describe "POST /api/segments/preview", type: :request do
  before do
    ClickhouseFixtures.load!
    allow(SegmentRules).to receive(:as_of).and_return(ClickhouseFixtures::AS_OF)
  end

  def preview(rules)
    post "/api/segments/preview", params: { rules: rules }, as: :json
  end

  it "returns the audience count and query time" do
    preview(ClickhouseFixtures::SEGMENTS[:season_lapsed_30_days])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["count"]).to eq(2)
    expect(response.parsed_body["query_ms"]).to be_a(Numeric)
  end

  it "returns 422 with the problems when rules are invalid" do
    preview({ match: "all", rules: [ { type: "attribute", field: "password", operator: "eq", value: "x" } ] })

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["errors"]).to include(/field must be one of/)
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
    failing = instance_double(ClickhouseClient)
    allow(failing).to receive(:query).and_raise(ClickhouseClient::Error, "boom")
    allow(ClickhouseClient).to receive(:new).and_return(failing)

    preview(ClickhouseFixtures::SEGMENTS[:season_lapsed_30_days])

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq("error" => "The segment query failed")
  end
end
