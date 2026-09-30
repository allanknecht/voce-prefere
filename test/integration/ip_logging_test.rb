require "test_helper"
require "stringio"

# Raw client IPs must never reach the Rails log ("Started GET "/" for <ip>").
class IpLoggingTest < ActionDispatch::IntegrationTest
  IPS = [ "203.0.113.7", "2001:db8::7", "2001:0db8:85a3:0000:0000:8a2e:0370:7334" ].freeze

  setup do
    @io = StringIO.new
    @original_logger = Rails.logger
    base = ActiveSupport::Logger.new(@io)
    base.formatter = ActiveSupport::Logger::SimpleFormatter.new
    # Same shape as production: BroadcastLogger around a tagged logger, wrapped by our scrubber
    Rails.logger = Privacy::IpScrubber.protect(ActiveSupport::BroadcastLogger.new(ActiveSupport::TaggedLogging.new(base)))
    Rails.logger.level = Logger::DEBUG
  end

  teardown { Rails.logger = @original_logger }

  test "the request-line middleware is our IP-free one" do
    assert_includes Rails.application.middleware.map(&:klass), Privacy::RackLogger
    refute_includes Rails.application.middleware.map(&:klass), Rails::Rack::Logger
  end

  test "Started line has no client address (REMOTE_ADDR and X-Forwarded-For, v4 and v6)" do
    IPS.each do |ip|
      get root_path, env: { "REMOTE_ADDR" => ip }
      get root_path, headers: { "X-Forwarded-For" => ip, "REMOTE_ADDR" => "10.1.2.3" }
      get root_path, headers: { "X-Forwarded-For" => "#{ip}, 10.9.9.9", "X-Real-IP" => ip, "Client-IP" => ip }
    end

    log = @io.string
    assert_match(/Started GET "\/" at /, log)
    IPS.each { |ip| refute_includes log, ip }
    refute_match(/\b\d{1,3}(\.\d{1,3}){3}\b/, log.gsub(/\d{4}-\d\d-\d\d[^\n]*/, ""), "an IPv4 literal reached the log")
    refute_match(/ for [0-9a-f:.]+ at /i, log)
  end

  test "IPs leaking through a controller error path are scrubbed as well" do
    Rails.logger.error("Vote creation error: connection from 203.0.113.7 refused")
    refute_includes @io.string, "203.0.113.7"
  end

  # Boots the real production environment (STDOUT logger, force_ssl, middleware stack)
  # in a subprocess, sends requests from fake client IPs and inspects what it logged.
  test "production boot: requests from 203.0.113.7 / 2001:db8::7 leave no IP in the STDOUT log" do
    out = ProductionBoot.run(<<~'RUBY', env: { "RAILS_LOG_LEVEL" => "debug" })
      [ "203.0.113.7", "2001:db8::7" ].each do |ip|
        env = { "REMOTE_ADDR" => ip, "HTTP_X_FORWARDED_FOR" => ip, "HTTPS" => "on", "HTTP_X_FORWARDED_PROTO" => "https" }
        Rack::MockRequest.new(Rails.application).get("https://voce.example/about", env)
        Rack::MockRequest.new(Rails.application).get("https://voce.example/nope", env)
      end
      Rails.logger.info("manual leak attempt from 203.0.113.7 and 2001:db8::7")
    RUBY

    assert_match(/Started GET "\/about" at /, out)
    assert_includes out, "[ip-redacted]" # the manual leak attempt was scrubbed
    refute_includes out, "203.0.113.7"
    refute_includes out, "2001:db8::7"
  end
end
