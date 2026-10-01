module Analytics
  # Retention: raw rows older than RETENTION_DAYS are folded into one `daily_stats` row per day
  # and then deleted, so the (free) database stays small. Idempotent (a second run finds nothing
  # to do), in ONE transaction, plain ActiveRecord (SQLite + PostgreSQL).
  #
  # No scheduler exists, so `run_if_due` is called opportunistically after recorded visits: at most
  # once per hour per process, and (through an atomic marker row in rate_limits, like the rate
  # limit purge) at most once per hour across processes. `rake stats:compact` runs it by hand.
  class Compactor
    CHECK_EVERY = 3600 # seconds
    @last_check = nil # nil = never ran in this process (the monotonic clock starts at boot, so 0.0 is not 'long ago')

    class << self
      attr_accessor :last_check

      def run_if_due(today: Analytics.today)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil if last_check && now - last_check < CHECK_EVERY

        self.last_check = now
        return nil unless RateLimiter.claim_once("analytics", "compact", 1.hour)

        new(today: today).run
      rescue StandardError => e
        Rails.logger.warn("analytics compaction failed: #{e.class}")
        nil
      end
    end

    def initialize(today: Analytics.today, retention_days: RETENTION_DAYS)
      @cutoff = today - retention_days # days strictly before this date are compacted
    end

    # => number of days compacted
    def run
      old_days = (Visit.where("day < ?", @cutoff).distinct.pluck(:day) + AnalyticsEvent.where("day < ?", @cutoff).distinct.pluck(:day)).uniq.sort
      return 0 if old_days.empty?

      compacted = 0
      old_days.each_slice(31) do |slice|
        ActiveRecord::Base.transaction do
          DayRollup.call(slice.first..slice.last).each do |day, data|
            next unless slice.include?(day)

            sources = data[:sources]
            hours = data[:hours]
            stat = DailyStat.find_or_initialize_by(day: day)
            stat.assign_attributes(data.except(:sources, :hours).merge(sources: sources, hours: hours))
            stat.save!
            compacted += 1
          end
          Visit.where(day: slice).delete_all
          AnalyticsEvent.where(day: slice).delete_all
        end
      end
      compacted
    end
  end
end
