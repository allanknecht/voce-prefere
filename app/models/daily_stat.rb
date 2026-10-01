# Aggregate of one (old) day, written by Analytics::Compactor before the raw rows are deleted.
class DailyStat < ApplicationRecord
  COUNTERS = %i[visits unique_visitors returning_visits via_share_visits votes voting_visitors polls_voted
                submits submitting_visitors shares sharing_visitors shared_link_visits reports
                mobile_visits desktop_visits tablet_visits].freeze

  validates :day, presence: true, uniqueness: true
end
