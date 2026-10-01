# A countable action (no text, no personal data). Table `events`.
class AnalyticsEvent < ApplicationRecord
  self.table_name = "events"

  KINDS = %w[vote submit_option share_click shared_link_visit report].freeze
  # what the browser beacon may report (the others are recorded by the server itself)
  BEACON_KINDS = %w[share_click].freeze

  validates :kind, inclusion: { in: KINDS }
end
