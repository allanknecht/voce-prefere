# frozen_string_literal: true

require "puma"
require "puma/error_logger"

module Privacy
  # Puma prints "(GET /path - (<X-Forwarded-For or REMOTE_ADDR>))" when a request
  # blows up outside of Rails. Keep the request line but never the client address.
  module PumaErrorLogger
    FORWARDING_HEADERS = %w[X-FORWARDED-FOR X-REAL-IP FORWARDED CLIENT-IP TRUE-CLIENT-IP CF-CONNECTING-IP].freeze

    def request_title(req)
      env = req.env
      format(::Puma::ErrorLogger::REQUEST_FORMAT,
             env["REQUEST_METHOD"], env["REQUEST_PATH"] || env["PATH_INFO"], "", "-")
    end

    def request_headers(req)
      headers = req.env.select { |key, _| key.start_with?("HTTP_") }
      headers = headers.map { |key, value| [ key[5..-1].tr("_", "-"), value ] }.to_h
      headers.reject! { |name, _| FORWARDING_HEADERS.include?(name) }
      headers.inspect
    end
  end
end

Puma::ErrorLogger.prepend(Privacy::PumaErrorLogger) unless Puma::ErrorLogger.include?(Privacy::PumaErrorLogger)
