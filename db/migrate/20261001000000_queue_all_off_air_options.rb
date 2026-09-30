# "Nothing is removed or hidden automatically": every option that is currently off the air
# (old `rejected`, old `pending`, including the ones kept off air by 3+ reports) is put into the
# review queue so the admin can decide: Aprovar = on the air, Excluir = delete.
#
#   * NOTHING is deleted and NOTHING is put on the air automatically (status is not touched).
#   * Idempotent: only sets a flag that is already the target value on a second run.
#   * One portable UPDATE, works on SQLite and PostgreSQL.
class QueueAllOffAirOptions < ActiveRecord::Migration[8.1]
  class MigrationOption < ActiveRecord::Base
    self.table_name = "options"
  end

  def up
    MigrationOption.reset_column_information
    MigrationOption.where.not(status: "approved").where(needs_review: false).update_all(needs_review: true)
  end

  def down
    # Not reversible on purpose: the previous state (rejected = out of the queue) carries no information
    # worth restoring, and un-queueing options the admin has not decided on would lose them.
  end
end
