require "test_helper"
require "stringio"

class IpScrubberTest < ActiveSupport::TestCase
  S = Privacy::IpScrubber

  test "scrubs IPv4" do
    assert_equal "for [ip-redacted] at", S.scrub("for 203.0.113.7 at")
    assert_equal "[ip-redacted], [ip-redacted]", S.scrub("10.0.0.1, 203.0.113.7")
  end

  test "scrubs IPv6 in every notation" do
    [ "2001:db8::1", "2001:0db8:85a3:0000:0000:8a2e:0370:7334", "::1", "fe80::1", "::ffff:203.0.113.7",
      "2001:db8:0:0:0:0:0:1", "2001:db8::", "1::" ].each do |ip|
      out = S.scrub("client #{ip} done")
      assert_equal "client [ip-redacted] done", out, "#{ip} leaked: #{out}"
    end
    assert_equal "[[ip-redacted]]:3000", S.scrub("[2001:db8::1]:3000")
  end

  test "does not mangle ordinary log text" do
    [ "12:34:56.789 done", "ActiveRecord::Base Foo::Bar", "Rails 8.1.4 ruby 3.3.6", "2026-09-30 00:51:02 -0300",
      "Completed 200 OK in 3ms (Views: 1.2ms | ActiveRecord: 0.3ms)" ].each do |text|
      assert_equal text, S.scrub(text)
    end
  end

  test "protects a plain logger, its << and its progname" do
    io = StringIO.new
    logger = S.protect(ActiveSupport::Logger.new(io))
    logger.info("hello 203.0.113.7")
    logger.info { "block 2001:db8::7" }
    logger.add(Logger::INFO, nil, "prog 198.51.100.9") { "x" }
    logger << "raw 192.0.2.1\n"
    refute_match(/\d+\.\d+\.\d+\.\d+|2001:db8/, io.string)
    assert_includes io.string, "[ip-redacted]"
  end

  test "protects every logger of a BroadcastLogger, including ones added later" do
    a = StringIO.new
    b = StringIO.new
    broadcast = ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(a))
    S.protect(broadcast)
    broadcast.broadcast_to(ActiveSupport::Logger.new(b))

    broadcast.info("from 203.0.113.7 / 2001:db8::1")
    [ a, b ].each do |io|
      refute_match(/203\.0\.113\.7|2001:db8/, io.string)
      assert_includes io.string, "[ip-redacted]"
    end
  end

  test "protects logger + tagged logging wrapper" do
    io = StringIO.new
    tagged = ActiveSupport::TaggedLogging.new(S.protect(ActiveSupport::Logger.new(io)))
    tagged.tagged("req-1") { tagged.info("ip=203.0.113.7") }
    refute_includes io.string, "203.0.113.7"
  end

  test "exceptions are scrubbed too" do
    io = StringIO.new
    logger = S.protect(ActiveSupport::Logger.new(io))
    logger.error(RuntimeError.new("boom from 203.0.113.7"))
    refute_includes io.string, "203.0.113.7"
  end
end
