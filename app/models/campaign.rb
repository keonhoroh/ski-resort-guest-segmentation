# A message sent to everyone in a segment who opted in to email.
# Stored in PostgreSQL. SendCampaignJob does the (pretend) sending.
class Campaign < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :segment
  has_many :campaign_sends, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 100 }
  validates :message, presence: true, length: { maximum: 2_000 }
  validates :status, inclusion: { in: STATUSES }

  def completed?
    status == "completed"
  end
end
