class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :option, null: false, foreign_key: true
      t.string :pair_hash, null: false, limit: 64

      t.timestamps
    end

    add_index :votes, :pair_hash
  end
end
