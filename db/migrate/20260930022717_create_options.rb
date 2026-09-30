class CreateOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :options do |t|
      t.string :text, null: false, limit: 120
      t.string :status, null: false, default: "pending"
      t.integer :report_count, null: false, default: 0
      t.string :category, limit: 50
      t.boolean :is_seed, null: false, default: false

      t.timestamps
    end

    add_index :options, :status
    add_index :options, :report_count
  end
end
