require "test_helper"

class OptionTest < ActiveSupport::TestCase
  test "new options default to pending status" do
    option = Option.create!(text: "Test option")
    assert_equal "pending", option.status
  end

  test "pending options do not appear in approved scope" do
    pending = Option.create!(text: "Pending", status: "pending")
    approved = Option.create!(text: "Approved", status: "approved")

    assert_includes Option.approved, approved
    refute_includes Option.approved, pending
  end

  test "only approved options can be drawn for pairs" do
    Option.create!(text: "Pending 1", status: "pending")
    Option.create!(text: "Pending 2", status: "pending")
    Option.create!(text: "Approved 1", status: "approved")
    Option.create!(text: "Approved 2", status: "approved")

    # PairGenerator only uses approved options
    pair = PairGenerator.random_pair
    assert_not_nil pair
    pair.each do |option|
      assert_equal "approved", option.status
    end
  end

  test "text is required" do
    option = Option.new(status: "pending")
    refute option.valid?
    assert_includes option.errors[:text], "can't be blank"
  end

  test "text has maximum length of 120 chars" do
    option = Option.new(text: "a" * 121, status: "pending")
    refute option.valid?
    assert_includes option.errors[:text], "is too long (maximum is 120 characters)"
  end
end
