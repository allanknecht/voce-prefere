require "test_helper"

class PrivacyTest < ActionDispatch::IntegrationTest
  test "GET / sets no cookie" do
    get root_path
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
  end

  test "GET /pairs/day sets no cookie" do
    # Create enough options for pair of day
    5.times { |i| Option.create!(text: "Option test #{i}", status: "approved") }

    get pairs_day_path

    # Should succeed if there are enough options
    if response.status == 200
      assert_response :success
      assert_nil response.headers["Set-Cookie"]
    else
      # Redirect to root if not enough options - still no cookie
      assert_response :redirect
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "POST /votes sets no cookie" do
    option = Option.create!(text: "Test", status: "approved")
    pair_hash = "#{option.id}-#{option.id + 1}"

    post votes_path,
         params: { option_id: option.id, pair_hash: pair_hash }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    # Rejected (no token) - and still no cookie
    assert_response :forbidden
    assert_nil response.headers["Set-Cookie"]
  end

  test "POST /options sets no cookie" do
    post options_path,
         params: { text: "Clean option", category: "good" }.to_json,
         headers: public_post_headers

    assert_response :success
    assert_nil response.headers["Set-Cookie"]
  end

  test "rate limiter never stores raw IP" do
    ip = "192.168.1.100"

    RateLimiter.record(ip, :vote)

    # Check database for any record containing the raw IP
    rate_limits = RateLimiter::RateLimit.all
    rate_limits.each do |limit|
      refute_equal ip, limit.hashed_key
      refute_includes limit.hashed_key, ip

      # Hashed key should be 64 chars (SHA256 hex)
      assert_equal 64, limit.hashed_key.length
    end
  end

  test "rate limiter hash requires SECRET_KEY_BASE to reverse" do
    ip = "192.168.1.100"

    # Record with one secret
    original_secret = ENV["SECRET_KEY_BASE"]
    ENV["SECRET_KEY_BASE"] = "secret1"
    RateLimiter.record(ip, :vote)
    hash1 = RateLimiter::RateLimit.first.hashed_key

    # Clean up
    RateLimiter::RateLimit.delete_all

    # Record same IP with different secret
    ENV["SECRET_KEY_BASE"] = "secret2"
    RateLimiter.record(ip, :vote)
    hash2 = RateLimiter::RateLimit.first.hashed_key

    # Hashes should be different (proving IP cannot be determined without secret)
    refute_equal hash1, hash2

    # Restore original secret
    ENV["SECRET_KEY_BASE"] = original_secret
  end
end
