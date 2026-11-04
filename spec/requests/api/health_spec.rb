require "rails_helper"

RSpec.describe "GET /api/health", type: :request do
  it "returns 200 when all three databases answer" do
    get "/api/health"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "status" => "ok",
      "services" => { "postgres" => "ok", "clickhouse" => "ok", "redis" => "ok" }
    )
  end

  it "returns 503 and names the failing database when one is down" do
    # Pretend ClickHouse is broken, without actually stopping it.
    broken = instance_double(ClickhouseClient)
    allow(broken).to receive(:query).and_raise(ClickhouseClient::Error, "boom")
    allow(ClickhouseClient).to receive(:new).and_return(broken)

    get "/api/health"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["status"]).to eq("degraded")
    expect(response.parsed_body["services"]).to include("clickhouse" => "error", "postgres" => "ok")
  end
end
