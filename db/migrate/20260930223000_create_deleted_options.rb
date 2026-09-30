# Keeps the TEXT of options that were deleted or rejected by the admin. Nothing personal:
# no IP, no author, no link to votes; only what the admin already sees in the option itself.
class CreateDeletedOptions < ActiveRecord::Migration[8.1]
  def change
    create_table :deleted_options do |t|
      t.string :text, limit: 120, null: false
      t.string :category, limit: 50
      t.string :reason, limit: 20, null: false # "manual" | "reprovada"
      t.datetime :deleted_at, null: false
    end
    add_index :deleted_options, :deleted_at
  end
end
