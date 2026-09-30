# Race-proof duplicate check for public submissions.
#
# `text_key` is the normalised text (Option.sort_key: case/accent/whitespace-insensitive) behind a
# UNIQUE index, so two simultaneous identical submits cannot both insert (the loser gets
# RecordNotUnique -> friendly 422).
#
# Legacy data may already contain duplicates (the public form had no duplicate check before):
# the lowest id of each group gets the key, the other ones keep NULL (NULLs never collide in a
# unique index on SQLite and PostgreSQL). NOTHING is deleted, edited or put on/off the air.
class AddTextKeyToOptions < ActiveRecord::Migration[8.1]
  class MigrationOption < ActiveRecord::Base
    self.table_name = "options"
  end

  def up
    add_column :options, :text_key, :string, limit: 255 unless column_exists?(:options, :text_key)
    MigrationOption.reset_column_information

    seen = {}
    MigrationOption.order(:id).pluck(:id, :text, :text_key).each do |id, text, current|
      key = text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.squish.presence
      next if key.nil? || seen.key?(key)

      seen[key] = id
      MigrationOption.where(id: id).update_all(text_key: key) unless current == key
    end
    # a re-run (or a partially filled column) must not leave a key on a later duplicate
    MigrationOption.where.not(id: seen.values).where.not(text_key: nil).update_all(text_key: nil)

    add_index :options, :text_key, unique: true unless index_exists?(:options, :text_key)
  end

  def down
    remove_index :options, :text_key if index_exists?(:options, :text_key)
    remove_column :options, :text_key if column_exists?(:options, :text_key)
  end
end
