# One page view. Holds NO personal data (see the migration): no IP, no user agent, no URL.
class Visit < ApplicationRecord
  SCREENS = %w[home pair results day controversial about other].freeze
  PAIR_SCREENS = %w[pair results day].freeze
  DEVICES = %w[mobile desktop tablet].freeze
end
