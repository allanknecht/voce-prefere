module Analytics
  # Per-day aggregates computed from the raw `visits` / `events` rows. The ONE implementation
  # behind both the admin statistics page (recent days) and the compaction into `daily_stats`.
  #
  # Counts of "visitors" are visitor-days: the hash rotates daily, so the same person on two
  # days is two visitors.
  class DayRollup
    SOURCES_KEPT = 20

    # { Date => { visits:, unique_visitors:, ..., sources: {"google.com" => 3}, hours: [24 ints] } }
    # for every day in `range` that has at least one raw row.
    def self.call(range)
      new(range).call
    end

    def initialize(range)
      @range = range
    end

    def call
      visits = Visit.where(day: @range)
      events = AnalyticsEvent.where(day: @range)

      visit_count = visits.group(:day).count
      unique = visits.group(:day).distinct.count(:visitor_hash)
      returning = visits.where(returning_visit: true).group(:day).count
      via_share = visits.where(via_share: true).group(:day).count
      devices = visits.group(:day, :device).count
      sources = visits.group(:day, :source).count
      hours = visits.group(:day, :hour).count

      ev_count = events.group(:day, :kind).count
      ev_visitors = events.group(:day, :kind).distinct.count(:visitor_hash)
      polls = events.where(kind: "vote").where.not(pair_hash: nil).distinct.pluck(:day, :visitor_hash, :pair_hash)
                    .group_by(&:first).transform_values(&:size)

      days = (visit_count.keys + ev_count.keys.map(&:first)).uniq.sort
      days.each_with_object({}) do |day, out|
        out[day] = {
          visits: visit_count[day].to_i, unique_visitors: unique[day].to_i,
          returning_visits: returning[day].to_i, via_share_visits: via_share[day].to_i,
          votes: ev_count[[ day, "vote" ]].to_i, voting_visitors: ev_visitors[[ day, "vote" ]].to_i, polls_voted: polls[day].to_i,
          submits: ev_count[[ day, "submit_option" ]].to_i, submitting_visitors: ev_visitors[[ day, "submit_option" ]].to_i,
          shares: ev_count[[ day, "share_click" ]].to_i, sharing_visitors: ev_visitors[[ day, "share_click" ]].to_i,
          shared_link_visits: ev_count[[ day, "shared_link_visit" ]].to_i, reports: ev_count[[ day, "report" ]].to_i,
          mobile_visits: devices[[ day, "mobile" ]].to_i, desktop_visits: devices[[ day, "desktop" ]].to_i,
          tablet_visits: devices[[ day, "tablet" ]].to_i,
          sources: top_sources(sources, day),
          hours: Array.new(24) { |h| hours[[ day, h ]].to_i }
        }
      end
    end

    private

    def top_sources(sources, day)
      mine = sources.select { |(d, _), _| d == day }.map { |(_, name), n| [ name, n ] }.sort_by { |name, n| [ -n, name ] }
      head = mine.first(SOURCES_KEPT).to_h
      rest = mine.drop(SOURCES_KEPT).sum { |_, n| n }
      head["outros"] = head.fetch("outros", 0) + rest if rest.positive?
      head
    end
  end
end
