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

ActiveRecord::Schema[8.1].define(version: 2026_09_30_120000) do
  create_table "options", force: :cascade do |t|
    t.string "text", limit: 120, null: false
    t.string "status", default: "pending", null: false
    t.integer "report_count", default: 0, null: false
    t.string "category", limit: 50
    t.boolean "is_seed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["report_count"], name: "index_options_on_report_count"
    t.index ["status", "id"], name: "index_options_on_status_and_id"
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
