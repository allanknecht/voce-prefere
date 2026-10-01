module Analytics
  # Everything /admin/stats shows, for the last `days` days (America/Sao_Paulo), from raw rows
  # for the recent days and `daily_stats` for the older (compacted) ones.
  class Report
    PERIODS = [ 7, 30, 90 ].freeze
    DEFAULT_PERIOD = 30

    attr_reader :days, :range, :per_day

    def self.period(value)
      PERIODS.include?(value.to_i) ? value.to_i : DEFAULT_PERIOD
    end

    def initialize(days: DEFAULT_PERIOD, today: Analytics.today)
      @days = self.class.period(days)
      @today = today
      @range = (today - (@days - 1))..today
      @per_day = load_days
    end

    def dates
      @range.to_a
    end

    def day(date)
      per_day[date] || EMPTY_DAY
    end

    EMPTY_DAY = { visits: 0, unique_visitors: 0, returning_visits: 0, via_share_visits: 0, votes: 0, voting_visitors: 0,
                  polls_voted: 0, submits: 0, submitting_visitors: 0, shares: 0, sharing_visitors: 0, shared_link_visits: 0,
                  reports: 0, mobile_visits: 0, desktop_visits: 0, tablet_visits: 0, sources: {}, hours: Array.new(24, 0) }.freeze

    def total(key)
      per_day.values.sum { |d| d[key].to_i }
    end

    # visitor-days: the same person on two days counts twice
    def unique_visitors = total(:unique_visitors)
    def visits = total(:visits)
    def votes = total(:votes)
    def returning_share = visits.zero? ? 0.0 : (total(:returning_visits) * 100.0 / visits).round(1)
    def votes_per_voter = total(:voting_visitors).zero? ? 0.0 : (votes.to_f / total(:voting_visitors)).round(2)
    def polls_per_voter = total(:voting_visitors).zero? ? 0.0 : (total(:polls_voted).to_f / total(:voting_visitors)).round(2)

    # visitou -> votou -> enviou opção -> compartilhou (visitor-days)
    def funnel
      [ [ "Visitou", unique_visitors ], [ "Votou", total(:voting_visitors) ],
        [ "Enviou opção", total(:submitting_visitors) ], [ "Compartilhou", total(:sharing_visitors) ] ]
    end

    # [[name, visits]] biggest first; "direto" and shared-link visits are included as such
    def sources
      sums = Hash.new(0)
      per_day.each_value { |d| d[:sources].each { |name, n| sums[name] += n.to_i } }
      sums.sort_by { |name, n| [ -n, name ] }
    end

    def hours
      Array.new(24) { |h| per_day.values.sum { |d| d[:hours][h].to_i } }
    end

    def devices
      { "Celular" => total(:mobile_visits), "Computador" => total(:desktop_visits), "Tablet" => total(:tablet_visits) }
    end

    # [{pair_hash:, options: [Option, Option], votes:}] most voted in the period (all vote rows)
    def top_polls(limit = 10)
      counts = Vote.where(created_at: period_time_range).group(:pair_hash).count.sort_by { |hash, n| [ -n, hash ] }.first(limit)
      options = Option.where(id: counts.flat_map { |hash, _| hash.split("-").map(&:to_i) }).index_by(&:id)
      counts.map { |hash, n| { pair_hash: hash, options: hash.split("-").map { |id| options[id.to_i] }, votes: n } }
    end

    def controversial_polls(limit = 10)
      PairGenerator.controversial_pairs(limit: limit, min_votes: 10)
    end

    def raw_days_available?
      Visit.where(day: @range).exists? || AnalyticsEvent.where(day: @range).exists?
    end

    private

    def load_days
      raw = DayRollup.call(@range)
      stored = DailyStat.where(day: @range).where.not(day: raw.keys).index_by(&:day)
      raw.merge(stored.transform_values { |s| stat_to_hash(s) })
    end

    def stat_to_hash(stat)
      hash = DailyStat::COUNTERS.index_with { |key| stat[key].to_i }
      hash[:sources] = (stat.sources || {}).transform_values(&:to_i)
      hash[:hours] = Array.new(24) { |h| (stat.hours || [])[h].to_i }
      hash
    end

    def period_time_range
      @range.first.in_time_zone(Analytics::TIME_ZONE).beginning_of_day..@range.last.in_time_zone(Analytics::TIME_ZONE).end_of_day
    end
  end
end
