# Review queue + good/bad category for options. NOTHING is deleted.
#
#   * options.needs_review (boolean, default false): the persistent review queue (/admin/review).
#   * options.category already exists (string(50), unused until now): from now on "good" | "bad".
#
# Data:
#   * every option gets a category from OptionClassifier (heuristic, see the class; the admin
#     can change it in /admin/options). Old free-text category values were never set by the UI.
#   * approved  -> stays approved, not in the queue
#   * pending   -> becomes visible (approved) and enters the queue, EXCEPT options that went
#                  back to pending because of reports (report_count >= 3): those stay off air
#                  and wait in the queue
#   * rejected  -> stays hidden, not in the queue (all rows and votes are kept)
#
# Plain SQL-portable statements (per-row UPDATEs on a tiny table): works on SQLite and PostgreSQL.
class AddReviewQueueAndCategoriesToOptions < ActiveRecord::Migration[8.1]
  class MigrationOption < ActiveRecord::Base
    self.table_name = "options"
  end

  def up
    add_column :options, :needs_review, :boolean, null: false, default: false
    add_index :options, :needs_review

    MigrationOption.reset_column_information
    MigrationOption.find_each do |option|
      attrs = { category: OptionClassifier.call(option.text) }
      if option.status == "pending"
        attrs[:needs_review] = true
        attrs[:status] = "approved" if option.report_count.to_i < 3
      end
      option.update_columns(attrs) # no callbacks, no updated_at change
    end
  end

  def down
    # Items in the queue go back to "pending" (the old review state); categories are left as they are.
    MigrationOption.reset_column_information
    MigrationOption.where(needs_review: true).update_all(status: "pending")
    remove_index :options, :needs_review
    remove_column :options, :needs_review
  end
end
