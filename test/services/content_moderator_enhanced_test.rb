require "test_helper"

class ContentModeratorEnhancedTest < ActiveSupport::TestCase
  def setup
    # Set test blocklists with a term we can test normalization on
    ENV["MODERATION_BLOCKLIST"] = "badword,offensive"
    ENV["MODERATION_NAMES_BLOCKLIST"] = "testbrand"
    ContentModerator.reset_lists!
  end

  def teardown
    ENV.delete("MODERATION_BLOCKLIST")
    ENV.delete("MODERATION_NAMES_BLOCKLIST")
    ContentModerator.reset_lists!
  end

  test "normalizes accents" do
    result = ContentModerator.check("Eu prefiro bádwórd")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "detects leetspeak - b4dw0rd" do
    result = ContentModerator.check("Eu prefiro b4dw0rd")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "detects spacing tricks - b a d w o r d" do
    result = ContentModerator.check("b a d w o r d")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "detects mixed tricks - b á d w ó r d" do
    result = ContentModerator.check("b á d w ó r d")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "detects profanity with caps and spacing" do
    result = ContentModerator.check("B A D W O R D")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "approves clean text with accents" do
    result = ContentModerator.check("Ter super velocidáde")
    assert result[:approved]
  end

  test "detects brand names with spaces" do
    result = ContentModerator.check("Comprar na t e s t b r a n d")
    refute result[:approved]
    assert_includes result[:reasons], :proper_names
  end
end
