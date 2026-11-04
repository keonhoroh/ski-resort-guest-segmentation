# Records that a campaign was (pretend) sent to one guest.
# A unique index on (campaign_id, guest_id) means each guest appears once at most.
class CampaignSend < ApplicationRecord
  belongs_to :campaign
end
