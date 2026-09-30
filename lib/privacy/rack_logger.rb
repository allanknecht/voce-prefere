# frozen_string_literal: true

require "rails"

module Privacy
  # Drop-in replacement for Rails::Rack::Logger. Rails' version logs
  #   Started GET "/" for 203.0.113.7 at 2026-01-01 ...
  # This one never reads the client address.
  class RackLogger < Rails::Rack::Logger
    private

    def started_request_message(request)
      format('Started %s "%s" at %s', request.raw_request_method, request.filtered_path, Time.now)
    end
  end
end
