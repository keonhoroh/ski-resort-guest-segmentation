# Sends a campaign to every opted-in guest in its segment, in batches.
# Nothing is really sent: each "send" is a row in campaign_sends.
#
# Safe to retry. If the job crashes partway and runs again:
#   - it carries on after the last guest it already sent to, and
#   - the unique index on campaign_sends refuses duplicates anyway,
# so no guest is ever counted twice.
#
#   SendCampaignJob.perform_later(campaign.id)
class SendCampaignJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 1_000

  # If ClickHouse fails, try again in a few seconds, up to 3 times in total.
  retry_on ClickhouseClient::Error, wait: 5.seconds, attempts: 3 do |job, error|
    Rails.logger.error("Campaign #{job.arguments.first} failed: #{error.message}")
    Campaign.where(id: job.arguments.first).update_all(status: "failed", finished_at: Time.current)
  end

  # The campaign was deleted (with its segment) before the job ran.
  discard_on ActiveRecord::RecordNotFound

  def perform(campaign_id, batch_size: BATCH_SIZE)
    campaign = Campaign.find(campaign_id)
    return if campaign.completed?

    client = ClickhouseClient.new
    builder = SegmentRules::QueryBuilder.new(campaign.rules, email_opt_in_only: true)

    campaign.update!(
      status: "running",
      started_at: campaign.started_at || Time.current,
      audience_count: campaign.audience_count || client.query(builder.count_sql, builder.params).first.fetch("count")
    )

    # Start after the highest guest ID already sent to (0 on the first run).
    after_guest_id = campaign.campaign_sends.maximum(:guest_id) || 0

    loop do
      rows = client.query(builder.guest_ids_batch_sql,
                          builder.params.merge(after_guest_id: after_guest_id, batch_size: batch_size))
      break if rows.empty?

      guest_ids = rows.map { |row| row.fetch("guest_id") }
      send_to(campaign, guest_ids)
      after_guest_id = guest_ids.last
    end

    campaign.update!(status: "completed", finished_at: Time.current)
  end

  private

  def send_to(campaign, guest_ids)
    # A real app would call an email service here. We pause briefly instead,
    # so the progress bar has something to show.
    sleep(send_delay)

    now = Time.current
    # insert_all skips rows that would break the unique index, so a guest
    # already sent to is silently left alone.
    CampaignSend.insert_all(
      guest_ids.map { |guest_id| { campaign_id: campaign.id, guest_id: guest_id, sent_at: now } },
      unique_by: %i[campaign_id guest_id]
    )

    # Count the rows instead of adding to the old number, so the total is
    # always exactly the number of different guests sent to.
    campaign.update!(sent_count: campaign.campaign_sends.count)
  end

  # Seconds to pause per batch (set to 0 in tests).
  def send_delay
    ENV.fetch("CAMPAIGN_SEND_DELAY", "0.2").to_f
  end
end
