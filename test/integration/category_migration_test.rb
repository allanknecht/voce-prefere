require "test_helper"
require Rails.root.join("db/migrate/20260930230000_add_review_queue_and_categories_to_options")

# Runs the data migration logic on an old-style database: nothing may be deleted.
class CategoryMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Vote.delete_all
    Option.delete_all
  end

  teardown do
    Vote.delete_all
    Option.delete_all
  end

  def run_data_migration
    # the schema already has the new column: replay only the data part of #up
    klass = AddReviewQueueAndCategoriesToOptions::MigrationOption
    klass.reset_column_information
    klass.find_each do |option|
      attrs = { category: OptionClassifier.call(option.text) }
      if option.status == "pending"
        attrs[:needs_review] = true
        attrs[:status] = "approved" if option.report_count.to_i < 3
      end
      option.update_columns(attrs)
    end
  end

  test "data migration: pending goes live and into the queue, rejected stays hidden and out of the queue, nothing is deleted" do
    now = Time.current
    rows = [
      { text: "Poder voar", status: "approved", report_count: 0 },
      { text: "Pendente normal", status: "pending", report_count: 0 },
      { text: "Pendente denunciada", status: "pending", report_count: 4 },
      { text: "Rejeitada antiga", status: "rejected", report_count: 0 },
      { text: "Chutar a parede com prego", status: "approved", report_count: 0 }
    ].map { |r| r.merge(category: nil, is_seed: false, created_at: now, updated_at: now) }
    Option.insert_all!(rows)
    voted = Option.find_by!(text: "Poder voar")
    other = Option.find_by!(text: "Pendente normal")
    Vote.create!(option: voted, pair_hash: PairGenerator.hash_for(voted, other))
    before_count = Option.count
    before_votes = Vote.count

    run_data_migration

    assert_equal before_count, Option.count
    assert_equal before_votes, Vote.count
    get = ->(text) { Option.find_by!(text: text) }
    assert_equal [ "approved", false, "good" ], [ get.("Poder voar").status, get.("Poder voar").needs_review, get.("Poder voar").category ]
    assert_equal [ "approved", true, "good" ], [ get.("Pendente normal").status, get.("Pendente normal").needs_review, get.("Pendente normal").category ]
    assert_equal [ "pending", true ], [ get.("Pendente denunciada").status, get.("Pendente denunciada").needs_review ]
    assert_equal [ "rejected", false ], [ get.("Rejeitada antiga").status, get.("Rejeitada antiga").needs_review ]
    assert_equal [ "approved", false, "bad" ], [ get.("Chutar a parede com prego").status, get.("Chutar a parede com prego").needs_review, get.("Chutar a parede com prego").category ]
    assert_empty Option.where(category: nil)
  end

  test "migration file is reversible and uses no engine-specific SQL" do
    source = Rails.root.join("db/migrate/20260930230000_add_review_queue_and_categories_to_options.rb").read
    assert_match(/def up/, source)
    assert_match(/def down/, source)
    assert_no_match(/execute|ILIKE|::text|unaccent/i, source)
  end
end
