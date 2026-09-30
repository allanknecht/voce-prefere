# frozen_string_literal: true

# Privacy: raw client IP addresses must never reach the logs.
#
# Layers (defence in depth):
#   1. Privacy::RackLogger replaces Rails' "Started GET ... for <ip>" line, so the
#      address is never even put into the log message.
#   2. Privacy::IpScrubber.protect(logger) wraps every logger (including each
#      logger inside an ActiveSupport::BroadcastLogger) so that any IPv4 / IPv6
#      literal that still ends up in a message is replaced before it is formatted.
#   3. lib/privacy/puma_error_logger.rb does the same for Puma's own error output.
module Privacy
  module IpScrubber
    REPLACEMENT = "[ip-redacted]"

    HEX = "[0-9A-Fa-f]{1,4}"
    V4 = '(?:\d{1,3}\.){3}\d{1,3}'

    IPV4 = /(?<![\d.])#{V4}(?![\d])/

    # IPv6 in all its forms: full, "::" compressed, and IPv4-mapped.
    # Compressed forms require "::" and the full form requires 8 groups, so plain
    # clock times such as 12:34:56 and Ruby constants such as ActiveRecord::Base
    # are never matched.
    IPV6 = /
      (?<!\w)
      (?:
        ::[fF]{4}:#{V4}
       |(?:#{HEX}:){7}#{HEX}
       |(?:#{HEX}:){1,7}:
       |(?:#{HEX}:){1,6}:#{HEX}
       |(?:#{HEX}:){1,5}(?::#{HEX}){1,2}
       |(?:#{HEX}:){1,4}(?::#{HEX}){1,3}
       |(?:#{HEX}:){1,3}(?::#{HEX}){1,4}
       |(?:#{HEX}:){1,2}(?::#{HEX}){1,5}
       |#{HEX}:(?::#{HEX}){1,6}
       |::(?:#{HEX}:){0,6}#{HEX}
      )
      (?!\w|:\w)
    /x

    module_function

    def scrub(text)
      text.to_s.gsub(IPV6, REPLACEMENT).gsub(IPV4, REPLACEMENT)
    end

    def scrub_message(msg)
      case msg
      when String then scrub(msg)
      when nil then msg
      when Exception then scrub("#{msg.message} (#{msg.class})\n#{msg.backtrace&.join("\n")}")
      else scrub(msg.inspect)
      end
    end

    # Extended onto a single ::Logger instance.
    module ScrubbedLogging
      def <<(msg)
        super(Privacy::IpScrubber.scrub_message(msg))
      end

      private

      def format_message(severity, datetime, progname, msg)
        progname = Privacy::IpScrubber.scrub(progname) if progname.is_a?(String)
        super(severity, datetime, progname, Privacy::IpScrubber.scrub_message(msg))
      end
    end

    # Extended onto an ActiveSupport::BroadcastLogger so that loggers added later
    # with #broadcast_to are protected as well.
    module BroadcastProtection
      def broadcast_to(*loggers)
        loggers.each { |logger| Privacy::IpScrubber.protect(logger) }
        super
      end
    end

    def protect(logger)
      return logger if logger.nil?

      if logger.is_a?(ActiveSupport::BroadcastLogger)
        logger.extend(BroadcastProtection) unless logger.is_a?(BroadcastProtection)
        logger.broadcasts.each { |child| protect(child) }
      elsif !logger.is_a?(ScrubbedLogging)
        logger.extend(ScrubbedLogging)
      end
      logger
    end
  end
end
