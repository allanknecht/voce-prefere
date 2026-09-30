require_relative "../../lib/admin_secret"

# Fail fast: never boot production with a missing/default admin password.
# (Skipped for `assets:precompile` in the Docker build, which sets SECRET_KEY_BASE_DUMMY.)
AdminSecret.validate! if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
