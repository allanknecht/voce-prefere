require "test_helper"

class ContentModeratorTest < ActiveSupport::TestCase
  def setup
    # Set test blocklists
    ENV["MODERATION_BLOCKLIST"] = "testbad,offensive,explicit"
    ENV["MODERATION_NAMES_BLOCKLIST"] = "testpolitician,testbrand,testcelebrity"
    ContentModerator.reset_lists!
  end

  def teardown
    ENV.delete("MODERATION_BLOCKLIST")
    ENV.delete("MODERATION_NAMES_BLOCKLIST")
    ContentModerator.reset_lists!
  end

  test "approves clean content" do
    result = ContentModerator.check("Ter super velocidade")
    assert result[:approved]
    assert_empty result[:reasons]
  end

  test "rejects profanity from blocklist" do
    result = ContentModerator.check("Eu prefiro testbad")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "rejects explicit content from blocklist" do
    result = ContentModerator.check("Fazer um explicit")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "rejects known proper names from blocklist" do
    result = ContentModerator.check("Votar no testpolitician")
    refute result[:approved]
    assert_includes result[:reasons], :proper_names
  end

  test "rejects brand names from blocklist" do
    result = ContentModerator.check("Comprar na testbrand")
    refute result[:approved]
    assert_includes result[:reasons], :proper_names
  end

  test "detects capitalized proper names in middle of text" do
    result = ContentModerator.check("Votar em João Silva")
    refute result[:approved]
    assert_includes result[:reasons], :proper_names
  end

  test "detects a full person name with connector" do
    refute ContentModerator.check("Namorar a Maria da Silva")[:approved]
  end

  test "does not flag a single capitalized word in the middle" do
    [ "Viver no Brasil para sempre", "Ganhar na Loteria", "Assistir Netflix o dia todo", "Passar o Natal na praia" ].each do |text|
      result = ContentModerator.check(text)
      assert result[:approved], "expected #{text.inspect} to be approved, got #{result[:reasons].inspect}"
    end
  end

  test "does not flag well known multi-word places" do
    assert ContentModerator.check("Morar em São Paulo")[:approved]
    assert ContentModerator.check("Viajar para o Rio de Janeiro")[:approved]
  end

  test "sentence-initial capitals, acronyms and punctuation are fine" do
    assert ContentModerator.check("Ter WiFi perfeito, sempre.")[:approved]
    assert ContentModerator.check("Comer Pizza")[:approved]
  end

  test "blocklisted multi-word names are rejected even when lowercase" do
    ENV["MODERATION_NAMES_BLOCKLIST"] = "joao exemplo, ana"
    ContentModerator.reset_lists!
    refute ContentModerator.check("votar no joão exemplo")[:approved]
    refute ContentModerator.check("Sair com a Ana hoje")[:approved]
  end

  test "short blocklisted names only match whole words" do
    ENV["MODERATION_NAMES_BLOCKLIST"] = "ana"
    ContentModerator.reset_lists!
    assert ContentModerator.check("Comer banana todo dia")[:approved]
  end

  test "allows first word to be capitalized" do
    result = ContentModerator.check("Comer pizza todo dia")
    assert result[:approved]
  end

  test "allows all lowercase text" do
    result = ContentModerator.check("poder voar livremente")
    assert result[:approved]
  end

  test "case insensitive profanity check" do
    result = ContentModerator.check("Eu prefiro TESTBAD")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "uses default list when env var not set" do
    ENV.delete("MODERATION_BLOCKLIST")
    ContentModerator.reset_lists!

    # Default list has harmless examples
    result = ContentModerator.check("palavrao1")
    refute result[:approved]
    assert_includes result[:reasons], :profanity
  end

  test "loads comma-separated list from env" do
    ENV["MODERATION_BLOCKLIST"] = "bad1,bad2,bad3"
    ContentModerator.reset_lists!

    result = ContentModerator.check("bad2")
    refute result[:approved]
  end

  test "loads newline-separated list from env" do
    ENV["MODERATION_BLOCKLIST"] = "bad1\nbad2\nbad3"
    ContentModerator.reset_lists!

    result = ContentModerator.check("bad3")
    refute result[:approved]
  end
end
