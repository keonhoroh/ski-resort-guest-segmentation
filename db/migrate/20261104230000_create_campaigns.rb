class CreateCampaigns < ActiveRecord::Migration[8.1]
  def change
    # One row per launched campaign.
    create_table :campaigns do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :message, null: false
      # A copy of the segment's rules at launch, so editing the segment later
      # does not change who a running campaign sends to.
      t.jsonb :rules, null: false
      t.string :status, null: false, default: "queued"
      t.integer :audience_count
      t.integer :sent_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    # One row per guest a campaign has (pretend) sent to.
    create_table :campaign_sends do |t|
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :guest_id, null: false
      t.datetime :sent_at, null: false
    end

    # The database refuses a second row for the same guest in the same campaign.
    # This is what keeps a retried job from counting anyone twice.
    add_index :campaign_sends, %i[campaign_id guest_id], unique: true
  end
end
