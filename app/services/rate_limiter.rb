class RateLimiter
  LIMITS = {
    submit: { count: 5, window: 1.hour },
    vote: { count: 100, window: 1.hour },
    report: { count: 10, window: 1.hour },
    admin_login: { count: 5, window: 15.minutes }
  }.freeze

  def self.check(ip_address, action)
    new(ip_address, action).check
  end

  def self.record(ip_address, action)
    new(ip_address, action).record
  end

  def initialize(ip_address, action)
    @ip_address = ip_address
    @action = action.to_s
    @limit_config = LIMITS[@action.to_sym]
    raise ArgumentError, "Unknown action: #{action}" unless @limit_config
  end

  def check
    cleanup_expired
    current_count < limit
  end

  def record
    cleanup_expired

    key = hashed_key
    expires_at = Time.current + window

    # Try to find existing record
    rate_limit = RateLimit.find_by(hashed_key: key)

    if rate_limit
      rate_limit.increment!(:count)
      rate_limit.update!(expires_at: expires_at) if rate_limit.expires_at < expires_at
    else
      RateLimit.create!(
        hashed_key: key,
        action: @action,
        count: 1,
        expires_at: expires_at
      )
    end

    true
  rescue => e
    Rails.logger.error("Rate limiter error: #{e.message}")
    true
  end

  def current_count
    cleanup_expired
    rate_limit = RateLimit.find_by(hashed_key: hashed_key)
    rate_limit&.count || 0
  end

  private

  def hashed_key
    # Hash IP with rotating salt for privacy
    # Salt rotates every window period to limit data retention
    salt = salt_for_window
    Digest::SHA256.hexdigest("#{salt}:#{@ip_address}:#{@action}")
  end

  def salt_for_window
    # Generate salt based on SECRET_KEY_BASE + current time window
    # This ensures hashed_key is not reversible to IP without the secret
    # Salt rotates every window period (e.g., every hour)
    secret = ENV["SECRET_KEY_BASE"].presence || Rails.application.secret_key_base
    window_start = (Time.current.to_i / window.to_i) * window.to_i
    "#{secret}:#{window_start}"
  end

  def limit
    @limit_config[:count]
  end

  def window
    @limit_config[:window]
  end

  def cleanup_expired
    RateLimit.where("expires_at < ?", Time.current).delete_all
  rescue => e
    Rails.logger.error("Rate limit cleanup error: #{e.message}")
  end

  class RateLimit < ApplicationRecord
    self.primary_key = :hashed_key
  end
end
