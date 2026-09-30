require "test_helper"

class VoteTest < ActiveSupport::TestCase
  def setup
    @option1 = Option.create!(text: "Option 1", status: "approved")
    @option2 = Option.create!(text: "Option 2", status: "approved")
    @pair_hash = [ @option1.id, @option2.id ].sort.join("-")
  end

  test "calculates pair statistics" do
    # 7 votes for option1, 3 votes for option2
    7.times { Vote.create!(option: @option1, pair_hash: @pair_hash) }
    3.times { Vote.create!(option: @option2, pair_hash: @pair_hash) }

    stats = Vote.pair_stats(@pair_hash)

    assert_equal 70.0, stats[@option1.id]
    assert_equal 30.0, stats[@option2.id]
  end

  test "returns empty hash for pair with no votes" do
    stats = Vote.pair_stats("999-1000")
    assert_empty stats
  end

  test "handles 50/50 split" do
    5.times { Vote.create!(option: @option1, pair_hash: @pair_hash) }
    5.times { Vote.create!(option: @option2, pair_hash: @pair_hash) }

    stats = Vote.pair_stats(@pair_hash)

    assert_equal 50.0, stats[@option1.id]
    assert_equal 50.0, stats[@option2.id]
  end
end
