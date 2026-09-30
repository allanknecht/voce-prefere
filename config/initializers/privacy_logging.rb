# Privacy: raw client IPs never reach the logs. See lib/privacy/ip_scrubber.rb.
require_relative "../../lib/privacy/ip_scrubber"
require_relative "../../lib/privacy/rack_logger"

# 1. Never put the IP into the "Started GET ..." request line.
Rails.application.config.middleware.swap Rails::Rack::Logger, Privacy::RackLogger, Rails.application.config.log_tags

# 2. Scrub anything IP-shaped from every logger (BroadcastLogger children included).
Privacy::IpScrubber.protect(Rails.logger)
Rails.application.config.after_initialize { Privacy::IpScrubber.protect(Rails.logger) }

# 3. Puma's own error output ("(GET /path - (<ip>))") lives outside Rails' logger.
require_relative "../../lib/privacy/puma_error_logger"
