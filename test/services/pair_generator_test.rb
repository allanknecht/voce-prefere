require "test_helper"

class PairGeneratorTest < ActiveSupport::TestCase
  def setup
    # Create test options
    @option1 = Option.create!(text: "Opção 1", status: "approved")
    @option2 = Option.create!(text: "Opção 2", status: "approved")
    @option3 = Option.create!(text: "Opção 3", status: "approved")
  end

  test "generates random pair" do
    pair = PairGenerator.random_pair
    assert_not_nil pair
    assert_equal 2, pair.length
    assert_kind_of Option, pair[0]
    assert_kind_of Option, pair[1]
    assert_not_equal pair[0].id, pair[1].id
  end

  test "returns nil when less than 2 options" do
    Option.destroy_all
    Option.create!(text: "Only one", status: "approved")

    pair = PairGenerator.random_pair
    assert_nil pair
  end

  test "generates deterministic pair of day" do
    pair1 = PairGenerator.pair_of_day
    pair2 = PairGenerator.pair_of_day

    assert_equal pair1.map(&:id).sort, pair2.map(&:id).sort
  end

  test "finds pair by hash" do
    pair_hash = [ @option1.id, @option2.id ].sort.join("-")
    pair = PairGenerator.pair_by_hash(pair_hash)

    assert_not_nil pair
    assert_equal 2, pair.length
    assert_includes pair.map(&:id), @option1.id
    assert_includes pair.map(&:id), @option2.id
  end

  test "returns nil for invalid pair hash" do
    pair = PairGenerator.pair_by_hash("999-1000")
    assert_nil pair
  end

  test "calculates controversy score" do
    pair_hash = [ @option1.id, @option2.id ].sort.join("-")

    # Create votes: 5 for option1, 5 for option2 (perfect 50/50)
    5.times { Vote.create!(option: @option1, pair_hash: pair_hash) }
    5.times { Vote.create!(option: @option2, pair_hash: pair_hash) }

    controversial = PairGenerator.controversial_pairs(limit: 1, min_votes: 5)

    assert_equal 1, controversial.length
    assert_equal pair_hash, controversial[0][:pair_hash]
    assert_equal 10, controversial[0][:total_votes]
    assert_in_delta 100.0, controversial[0][:controversy], 1.0
  end
end
