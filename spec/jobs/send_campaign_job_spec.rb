require "rails_helper"

RSpec.describe SendCampaignJob do
  include ActiveJob::TestHelper

  # Every guest in the fixture. All but guest 3 opted in to email.
  let(:everyone) do
    { "match" => "all",
      "rules" => [ { "type" => "attribute", "field" => "pass_type", "operator" => "in",
                     "value" => %w[season multi_day day] } ] }
  end
  let(:opted_in_guests) { [ 1, 2, 4, 5, 6, 7, 8, 9 ] }

  let(:segment) { Segment.create!(name: "Everyone", rules: everyone) }
  let(:campaign) { segment.campaigns.create!(name: "Spring sale", message: "20% off", rules: everyone) }

  before do
    ClickhouseFixtures.load!
    allow(SegmentRules).to receive(:as_of).and_return(ClickhouseFixtures::AS_OF)
  end

  def sent_guest_ids
    campaign.campaign_sends.order(:guest_id).pluck(:guest_id)
  end

  # Makes ClickHouse fail once, on the given batch fetch (1 = the first batch).
  def fail_once_on_batch(number)
    batches = 0
    allow_any_instance_of(ClickhouseClient).to receive(:query).and_wrap_original do |original, sql, *rest|
      if sql.include?("after_guest_id")
        batches += 1
        raise ClickhouseClient::Error, "connection lost" if batches == number
      end
      original.call(sql, *rest)
    end
  end

  it "sends to every opted-in guest and records the total" do
    described_class.perform_now(campaign.id, batch_size: 3)

    campaign.reload
    expect(campaign.status).to eq("completed")
    expect(campaign.audience_count).to eq(8)
    expect(campaign.sent_count).to eq(8)
    expect(sent_guest_ids).to eq(opted_in_guests)
    expect(campaign.started_at).to be_present
    expect(campaign.finished_at).to be_present
  end

  it "skips guests who did not opt in to email" do
    described_class.perform_now(campaign.id)

    expect(sent_guest_ids).not_to include(3)
  end

  it "survives a crash partway through without counting anyone twice" do
    fail_once_on_batch(2) # batch 1 (guests 1, 2, 4) succeeds, then ClickHouse drops out

    described_class.perform_now(campaign.id, batch_size: 3)

    # The first try stopped partway, and a retry is waiting in the queue.
    expect(campaign.reload.status).to eq("running")
    expect(campaign.sent_count).to eq(3)
    expect(enqueued_jobs.size).to eq(1)

    perform_enqueued_jobs # run the retry

    campaign.reload
    expect(campaign.status).to eq("completed")
    expect(campaign.sent_count).to eq(8)
    expect(sent_guest_ids).to eq(opted_in_guests)
  end

  it "does nothing if the job runs again after finishing" do
    described_class.perform_now(campaign.id, batch_size: 3)
    expect { described_class.perform_now(campaign.id, batch_size: 3) }
      .not_to(change { [ campaign.reload.sent_count, campaign.campaign_sends.count, campaign.finished_at ] })
  end

  it "still counts each guest once if a run starts over from the beginning" do
    described_class.perform_now(campaign.id, batch_size: 3)
    # Pretend the campaign never finished, and forget where it got to.
    campaign.update!(status: "running")
    allow_any_instance_of(ActiveRecord::Relation).to receive(:maximum).with(:guest_id).and_return(nil)

    described_class.perform_now(campaign.id, batch_size: 3)

    expect(campaign.reload.sent_count).to eq(8)
    expect(campaign.campaign_sends.count).to eq(8)
  end

  it "marks the campaign failed when ClickHouse keeps failing" do
    allow_any_instance_of(ClickhouseClient).to receive(:query).and_raise(ClickhouseClient::Error, "down")

    described_class.perform_now(campaign.id)
    2.times { perform_enqueued_jobs }

    expect(campaign.reload.status).to eq("failed")
    expect(enqueued_jobs).to be_empty
  end

  it "uses the rules saved on the campaign, not the segment's current rules" do
    segment.update!(rules: ClickhouseFixtures::SEGMENTS[:expert_scans_50_in_120_days])

    described_class.perform_now(campaign.id)

    expect(campaign.reload.sent_count).to eq(8)
  end
end
