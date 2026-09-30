require "test_helper"

class RateLimiterTest < ActiveSupport::TestCase
  def setup
    RateLimiter::RateLimit.delete_all
  end

  test "allows first request" do
    assert RateLimiter.check("192.168.1.1", :vote)
  end

  test "records request" do
    RateLimiter.record("192.168.1.1", :vote)

    assert_equal 1, RateLimiter.new("192.168.1.1", :vote).current_count
  end

  test "increments count on multiple requests" do
    3.times { RateLimiter.record("192.168.1.1", :vote) }

    assert_equal 3, RateLimiter.new("192.168.1.1", :vote).current_count
  end

  test "blocks after limit reached" do
    # Submit limit is 5 per hour
    5.times { RateLimiter.record("192.168.1.1", :submit) }

    refute RateLimiter.check("192.168.1.1", :submit)
  end

  test "different actions have separate limits" do
    5.times { RateLimiter.record("192.168.1.1", :submit) }

    assert RateLimiter.check("192.168.1.1", :vote)
  end

  test "different IPs have separate limits" do
    5.times { RateLimiter.record("192.168.1.1", :submit) }

    assert RateLimiter.check("192.168.1.2", :submit)
  end

  test "cleans up expired entries" do
    limiter = RateLimiter.new("192.168.1.1", :vote)
    limiter.record

    # Manually expire the entry
    RateLimiter::RateLimit.first.update!(expires_at: 1.hour.ago)

    assert_equal 0, limiter.current_count
  end

  test "uses hashed keys for privacy" do
    RateLimiter.record("192.168.1.1", :vote)

    # Ensure raw IP is not stored
    rate_limit = RateLimiter::RateLimit.first
    refute_equal "192.168.1.1", rate_limit.hashed_key
    assert_equal 64, rate_limit.hashed_key.length
  end
end
