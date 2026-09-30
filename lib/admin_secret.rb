# The admin password comes from ENV["ADMIN_SECRET"].
#
# In production the app refuses to boot when it is unset, blank, too short or still
# the well-known placeholder (see config/initializers/admin_secret.rb). There is
# deliberately no fallback in production.
module AdminSecret
  PLACEHOLDER = "change-me-in-production"
  DEV_DEFAULT = "dev-admin-secret"
  MIN_LENGTH = 16

  class ConfigurationError < StandardError; end

  module_function

  def value
    ENV["ADMIN_SECRET"].presence || (Rails.env.production? ? nil : DEV_DEFAULT)
  end

  def matches?(candidate)
    secret = value
    return false if secret.blank?

    ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(secret), Digest::SHA256.hexdigest(candidate.to_s))
  end

  def validate!
    secret = ENV["ADMIN_SECRET"].to_s.strip
    return if secret.length >= MIN_LENGTH && secret != PLACEHOLDER

    raise ConfigurationError,
          "ADMIN_SECRET must be set to a strong random value (at least #{MIN_LENGTH} characters, " \
          "not '#{PLACEHOLDER}') in production. Generate one with: openssl rand -hex 32"
  end
end
