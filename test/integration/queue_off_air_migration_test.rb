require "test_helper"
require Rails.root.join("db/migrate/20261001000000_queue_all_off_air_options")

# Replays the data migration on a legacy-style database: nothing deleted, nothing put on the air.
class QueueOffAirMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Vote.delete_all
    Option.delete_all
  end

  teardown do
    Vote.delete_all
    Option.delete_all
  end

  def migrate_up
    QueueAllOffAirOptions.new.suppress_messages { QueueAllOffAirOptions.new.up }
  end

  test "rejected and pending (incl. the 3+ reports ones) go to the queue, approved ones are untouched, nothing is deleted or put on the air" do
    rows = [
      [ "Rejeitada", "rejected", false, 0 ], [ "Pendente", "pending", false, 0 ], [ "Pendente denunciada", "pending", true, 4 ],
      [ "No ar", "approved", false, 0 ], [ "No ar em revisão", "approved", true, 1 ]
    ].map { |text, status, review, reports| { text: text, status: status, needs_review: review, report_count: reports, category: "good", is_seed: false, created_at: Time.current, updated_at: Time.current } }
    Option.insert_all!(rows)
    voted = Option.find_by!(text: "Rejeitada")
    Vote.create!(option: voted, pair_hash: "#{voted.id}-#{Option.find_by!(text: 'No ar').id}")
    snapshot = Option.order(:id).pluck(:text, :status, :report_count)

    migrate_up

    assert_equal snapshot, Option.order(:id).pluck(:text, :status, :report_count), "status and reports untouched, nothing deleted"
    assert_equal 1, Vote.count
    by = ->(text) { Option.find_by!(text: text) }
    assert by.("Rejeitada").needs_review
    assert by.("Pendente").needs_review
    assert by.("Pendente denunciada").needs_review
    refute by.("No ar").needs_review
    assert by.("No ar em revisão").needs_review
    assert_equal [ "No ar", "No ar em revisão" ], Option.approved.order(:id).pluck(:text)
  end

  test "idempotent: a second run changes nothing" do
    Option.insert_all!([ { text: "Rejeitada", status: "rejected", needs_review: false, report_count: 0, category: "bad", is_seed: false, created_at: Time.current, updated_at: Time.current } ])
    migrate_up
    first = Option.order(:id).pluck(:text, :status, :needs_review, :report_count, :updated_at)
    migrate_up
    assert_equal first, Option.order(:id).pluck(:text, :status, :needs_review, :report_count, :updated_at)
  end

  test "portable SQL only" do
    source = Rails.root.join("db/migrate/20261001000000_queue_all_off_air_options.rb").read
    assert_no_match(/execute|ILIKE|::text|unaccent/i, source)
  end
end
