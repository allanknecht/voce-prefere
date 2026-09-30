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

  test "sort_key ignores case, accents and extra spaces" do
    assert_equal "acao  x".squish, Option.sort_key("  AÇÃO   x ")
    assert_equal Option.sort_key("Comer açaí"), Option.sort_key("COMER ACAI")
  end

  test "admin_ids orders alphabetically and filters literally (LIKE wildcards are plain characters)" do
    b = Option.create!(text: "b 50%", status: "approved")
    a = Option.create!(text: "Á 50x", status: "pending")
    assert_equal [ a.id, b.id ], Option.admin_ids
    assert_equal [ b.id ], Option.admin_ids(query: "50%")
    assert_equal [ a.id ], Option.admin_ids(status: "pendentes")
    assert_equal [], Option.admin_ids(status: "rejeitadas")
  end

  test "admin_edit context refuses a duplicate of another option but not of itself" do
    one = Option.create!(text: "Igual", status: "approved")
    two = Option.create!(text: "Diferente", status: "approved")
    two.text = "IGUAL"
    refute two.valid?(:admin_edit)
    assert two.valid? # public creation rules are unchanged
    one.text = "igual"
    assert one.valid?(:admin_edit)
  end

  test "destroy_with_votes! removes own votes and votes of pairs containing the option, nothing else" do
    a = Option.create!(text: "A", status: "approved")
    b = Option.create!(text: "B", status: "approved")
    c = Option.create!(text: "C", status: "approved")
    Vote.create!(option: a, pair_hash: "#{a.id}-#{b.id}")
    Vote.create!(option: b, pair_hash: "#{a.id}-#{b.id}")
    Vote.create!(option: b, pair_hash: "#{b.id}-#{c.id}")
    a.destroy_with_votes!
    assert_equal 1, Vote.count
    assert_not Option.exists?(a.id)
  end
end
