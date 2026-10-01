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

ActiveRecord::Schema[8.1].define(version: 2026_10_02_000000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "daily_stats", force: :cascade do |t|
    t.date "day", null: false
    t.integer "visits", default: 0, null: false
    t.integer "unique_visitors", default: 0, null: false
    t.integer "returning_visits", default: 0, null: false
    t.integer "via_share_visits", default: 0, null: false
    t.integer "votes", default: 0, null: false
    t.integer "voting_visitors", default: 0, null: false
    t.integer "polls_voted", default: 0, null: false
    t.integer "submits", default: 0, null: false
    t.integer "submitting_visitors", default: 0, null: false
    t.integer "shares", default: 0, null: false
    t.integer "sharing_visitors", default: 0, null: false
    t.integer "shared_link_visits", default: 0, null: false
    t.integer "reports", default: 0, null: false
    t.integer "mobile_visits", default: 0, null: false
    t.integer "desktop_visits", default: 0, null: false
    t.integer "tablet_visits", default: 0, null: false
    t.json "sources", default: {}, null: false
    t.json "hours", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day"], name: "index_daily_stats_on_day", unique: true
  end

  create_table "deleted_options", force: :cascade do |t|
    t.string "text", limit: 120, null: false
    t.string "category", limit: 50
    t.string "reason", limit: 20, null: false
    t.datetime "deleted_at", null: false
    t.index ["deleted_at"], name: "index_deleted_options_on_deleted_at"
  end

  create_table "events", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.date "day", null: false
    t.integer "hour", limit: 1, null: false
    t.string "kind", limit: 24, null: false
    t.string "pair_hash", limit: 40
    t.integer "option_id"
    t.string "device", limit: 8, null: false
    t.string "visitor_hash", limit: 16, null: false
    t.index ["day", "kind"], name: "index_events_on_day_and_kind"
    t.index ["day", "visitor_hash"], name: "index_events_on_day_and_visitor_hash"
    t.index ["occurred_at"], name: "index_events_on_occurred_at"
  end

  create_table "options", force: :cascade do |t|
    t.string "text", limit: 120, null: false
    t.string "status", default: "pending", null: false
    t.integer "report_count", default: 0, null: false
    t.string "category", limit: 50
    t.boolean "is_seed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "needs_review", default: false, null: false
    t.string "text_key", limit: 255
    t.index ["needs_review"], name: "index_options_on_needs_review"
    t.index ["report_count"], name: "index_options_on_report_count"
    t.index ["status", "id"], name: "index_options_on_status_and_id"
    t.index ["text_key"], name: "index_options_on_text_key", unique: true
  end

  create_table "rate_limits", id: false, force: :cascade do |t|
    t.string "hashed_key", limit: 64, null: false
    t.string "action", limit: 50, null: false
    t.integer "count", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_rate_limits_on_expires_at"
    t.index ["hashed_key"], name: "index_rate_limits_on_hashed_key", unique: true
  end

  create_table "visits", force: :cascade do |t|
    t.datetime "occurred_at", null: false
    t.date "day", null: false
    t.integer "hour", limit: 1, null: false
    t.string "screen", limit: 16, null: false
    t.string "pair_hash", limit: 40
    t.string "device", limit: 8, null: false
    t.string "source", limit: 40, default: "direto", null: false
    t.boolean "via_share", default: false, null: false
    t.boolean "returning_visit", default: false, null: false
    t.string "visitor_hash", limit: 16, null: false
    t.index ["day", "visitor_hash"], name: "index_visits_on_day_and_visitor_hash"
    t.index ["occurred_at"], name: "index_visits_on_occurred_at"
  end

  create_table "votes", force: :cascade do |t|
    t.integer "option_id", null: false
    t.string "pair_hash", limit: 64, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["option_id"], name: "index_votes_on_option_id"
    t.index ["pair_hash", "option_id"], name: "index_votes_on_pair_hash_and_option_id"
  end

  add_foreign_key "votes", "options"
end
