class CreateRateLimits < ActiveRecord::Migration[8.1]
  def change
    create_table :rate_limits, id: false, primary_key: :hashed_key do |t|
      t.string :hashed_key, null: false, limit: 64
      t.string :action, null: false, limit: 50
      t.integer :count, null: false, default: 1
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :rate_limits, :hashed_key, unique: true
    add_index :rate_limits, :expires_at
  end
end
