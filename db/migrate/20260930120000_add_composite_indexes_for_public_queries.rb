# Indexes for the hot public queries. Already present (see db/schema.rb) and therefore NOT
# added again: votes(option_id), rate_limits(expires_at), rate_limits(hashed_key) UNIQUE,
# options(report_count).
#
# * votes(pair_hash, option_id): "SELECT option_id, COUNT(*) ... WHERE pair_hash = ? GROUP BY option_id"
#   (results of every pair, the vote response, the controversial ranking) can be answered from the
#   index alone. It also covers lookups by pair_hash, so the single-column pair_hash index is redundant.
# * options(status, id): "SELECT id FROM options WHERE status = 'approved' ORDER BY id" (random pair,
#   pair of the day) is an index-only, already ordered scan. Covers lookups by status too.
#
# Plain btree indexes only: works the same on SQLite (dev/test) and PostgreSQL (production).
class AddCompositeIndexesForPublicQueries < ActiveRecord::Migration[8.1]
  def change
    add_index :votes, [ :pair_hash, :option_id ], if_not_exists: true
    remove_index :votes, :pair_hash, if_exists: true

    add_index :options, [ :status, :id ], if_not_exists: true
    remove_index :options, :status, if_exists: true
  end
end
