# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_04_230000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "campaign_sends", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "guest_id", null: false
    t.datetime "sent_at", null: false
    t.index ["campaign_id", "guest_id"], name: "index_campaign_sends_on_campaign_id_and_guest_id", unique: true
  end

  create_table "campaigns", force: :cascade do |t|
    t.bigint "segment_id", null: false
    t.string "name", null: false
    t.text "message", null: false
    t.jsonb "rules", null: false
    t.string "status", default: "queued", null: false
    t.integer "audience_count"
    t.integer "sent_count", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["segment_id"], name: "index_campaigns_on_segment_id"
  end

  create_table "segments", force: :cascade do |t|
    t.string "name", null: false
    t.jsonb "rules", null: false
    t.integer "last_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "campaign_sends", "campaigns", on_delete: :cascade
  add_foreign_key "campaigns", "segments", on_delete: :cascade
end
