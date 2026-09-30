require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Code is not reloaded between requests.
  config.enable_reloading = false
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # TLS is terminated by the platform's proxy (Render), which sets X-Forwarded-Proto.
  # Force HTTPS: redirect http -> https, send Strict-Transport-Security (1 year,
  # includeSubDomains) and mark cookies Secure.
  config.force_ssl = true
  config.ssl_options = {
    hsts: { expires: 1.year, subdomains: true, preload: false },
    # The platform health check must not be redirected.
    redirect: { exclude: ->(request) { request.path == "/up" } }
  }

  # Log to STDOUT. Client IPs are removed from logs (see lib/privacy and
  # config/initializers/privacy_logging.rb); the request id is the only log tag.
  config.log_tags = [ :request_id ]
  config.logger = ActiveSupport::TaggedLogging.logger(STDOUT)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # No cache store needed (rate limiting uses the database, no Redis, no disk).
  config.cache_store = :null_store

  # Enable locale fallbacks for I18n.
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Host authorization is left open on purpose (Render gives you a *.onrender.com host and
  # you may add a custom domain). The CSRF/Origin checks compare against the request host.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
