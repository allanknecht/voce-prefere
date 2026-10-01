# First-party, privacy-first analytics. NO personal data: no IP, no user agent, no cookie id.
#
#   visits       one row per page view (short retention, compacted into daily_stats after ~90 days)
#   events       vote / submit_option / share_click / shared_link_visit / report (same retention)
#   daily_stats  one aggregate row per day, kept for long term
#
# `visitor_hash` = first 16 hex chars of HMAC-SHA256(daily_salt, ip|user_agent). The salt changes
# every day and is derived from the app secret, so the hash cannot be reversed to an IP/UA and
# cannot be linked across days. `day`/`hour` are in America/Sao_Paulo.
class CreateAnalyticsTables < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.datetime :occurred_at, null: false
      t.date :day, null: false
      t.integer :hour, null: false, limit: 1
      t.string :screen, null: false, limit: 16
      t.string :pair_hash, limit: 40
      t.string :device, null: false, limit: 8
      t.string :source, null: false, limit: 40, default: "direto"
      t.boolean :via_share, null: false, default: false
      t.boolean :returning_visit, null: false, default: false
      t.string :visitor_hash, null: false, limit: 16
    end
    add_index :visits, :occurred_at
    add_index :visits, [ :day, :visitor_hash ]

    create_table :events do |t|
      t.datetime :occurred_at, null: false
      t.date :day, null: false
      t.integer :hour, null: false, limit: 1
      t.string :kind, null: false, limit: 24
      t.string :pair_hash, limit: 40
      t.integer :option_id
      t.string :device, null: false, limit: 8
      t.string :visitor_hash, null: false, limit: 16
    end
    add_index :events, :occurred_at
    add_index :events, [ :day, :kind ]
    add_index :events, [ :day, :visitor_hash ]

    create_table :daily_stats do |t|
      t.date :day, null: false
      t.integer :visits, null: false, default: 0
      t.integer :unique_visitors, null: false, default: 0
      t.integer :returning_visits, null: false, default: 0
      t.integer :via_share_visits, null: false, default: 0
      t.integer :votes, null: false, default: 0
      t.integer :voting_visitors, null: false, default: 0
      t.integer :polls_voted, null: false, default: 0
      t.integer :submits, null: false, default: 0
      t.integer :submitting_visitors, null: false, default: 0
      t.integer :shares, null: false, default: 0
      t.integer :sharing_visitors, null: false, default: 0
      t.integer :shared_link_visits, null: false, default: 0
      t.integer :reports, null: false, default: 0
      t.integer :mobile_visits, null: false, default: 0
      t.integer :desktop_visits, null: false, default: 0
      t.integer :tablet_visits, null: false, default: 0
      t.json :sources, null: false, default: {}
      t.json :hours, null: false, default: []
      t.timestamps
    end
    add_index :daily_stats, :day, unique: true
  end
end
