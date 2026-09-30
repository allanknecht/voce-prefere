require "test_helper"
require Rails.root.join("db/migrate/20261001010000_add_text_key_to_options")

# Replays the data part of AddTextKeyToOptions on legacy data that already contains duplicates.
class TextKeyMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup { [ Vote, Option ].each(&:delete_all) }
  teardown { [ Vote, Option ].each(&:delete_all) }

  def migrate
    m = AddTextKeyToOptions.new
    m.verbose = false
    m.suppress_messages do
      m.remove_index :options, :text_key
      m.up
    end
  end

  test "legacy duplicates keep their rows (the oldest gets the key, the others NULL), the unique index is rebuilt, nothing is deleted or changed, idempotent" do
    now = Time.current
    rows = [ "Comer açaí", "COMER ACAI", "Outra", "  outra  ", "Única" ].map do |t|
      { text: t, status: "approved", category: "good", report_count: 0, is_seed: false, needs_review: false, text_key: nil, created_at: now, updated_at: now }
    end
    Option.insert_all!(rows)
    before = Option.order(:id).pluck(:text, :status, :needs_review, :report_count)

    2.times do
      migrate
      assert_equal before, Option.order(:id).pluck(:text, :status, :needs_review, :report_count)
      assert_equal [ "comer acai", nil, "outra", nil, "unica" ], Option.order(:id).pluck(:text_key)
    end
    assert_includes ActiveRecord::Base.connection.indexes(:options).select(&:unique).map(&:columns).flatten, "text_key"
    # new submissions of a legacy text are refused, unrelated ones work
    assert Option.text_taken?("comer AÇAÍ")
    refute Option.text_taken?("algo novo")
  end
end
