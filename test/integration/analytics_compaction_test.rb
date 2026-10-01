require "test_helper"

class AnalyticsCompactionTest < ActiveSupport::TestCase
  TODAY = Date.new(2026, 10, 10)
  OLD = TODAY - 100
  NEW = TODAY - 3

  setup do
    [ Visit, AnalyticsEvent, DailyStat ].each(&:delete_all)
    RateLimiter::RateLimit.delete_all
    Analytics::Compactor.last_check = nil
  end

  def visit!(day, visitor, hour: 10, **attrs)
    Visit.create!({ occurred_at: Time.utc(day.year, day.month, day.day) + (hour + 3).hours, day: day, hour: hour, screen: "home",
                    device: "mobile", source: "direto", visitor_hash: visitor }.merge(attrs))
  end

  def event!(day, kind, visitor, pair: nil)
    AnalyticsEvent.create!(occurred_at: Time.utc(day.year, day.month, day.day, 13), day: day, hour: 10, kind: kind, pair_hash: pair, device: "mobile", visitor_hash: visitor)
  end

  def seed_old_day
    visit!(OLD, "a", returning_visit: true, source: "google.com")
    visit!(OLD, "a", screen: "pair")
    visit!(OLD, "b", device: "desktop", via_share: true, source: "whatsapp", hour: 21)
    event!(OLD, "vote", "a", pair: "1-2")
    event!(OLD, "vote", "a", pair: "1-2")
    event!(OLD, "vote", "a", pair: "3-4")
    event!(OLD, "vote", "b", pair: "1-2")
    event!(OLD, "submit_option", "b")
    event!(OLD, "share_click", "b")
    event!(OLD, "report", "a")
    event!(OLD, "shared_link_visit", "b")
  end

  test "raw rows older than 90 days become one daily_stats row and are deleted; recent rows stay" do
    seed_old_day
    visit!(NEW, "z")
    event!(NEW, "vote", "z", pair: "1-2")
    assert_equal 1, Analytics::Compactor.new(today: TODAY).run
    assert_equal [ NEW ], Visit.pluck(:day).uniq
    assert_equal [ NEW ], AnalyticsEvent.pluck(:day).uniq
    s = DailyStat.find_by!(day: OLD)
    assert_equal [ 3, 2, 1, 1 ], [ s.visits, s.unique_visitors, s.returning_visits, s.via_share_visits ]
    assert_equal [ 4, 2, 3 ], [ s.votes, s.voting_visitors, s.polls_voted ] # a: 2 polls, b: 1 poll
    assert_equal [ 1, 1, 1, 1, 1 ], [ s.submits, s.submitting_visitors, s.shares, s.sharing_visitors, s.reports ]
    assert_equal 1, s.shared_link_visits
    assert_equal [ 2, 1, 0 ], [ s.mobile_visits, s.desktop_visits, s.tablet_visits ]
    assert_equal({ "google.com" => 1, "direto" => 1, "whatsapp" => 1 }, s.sources)
    assert_equal [ 2, 1, 3 ], [ s.hours[10], s.hours[21], s.hours.sum ]
    assert_equal 24, s.hours.size
  end

  test "idempotent: a second run finds nothing, does not duplicate or change the stored day" do
    seed_old_day
    assert_equal 1, Analytics::Compactor.new(today: TODAY).run
    before = DailyStat.find_by!(day: OLD).attributes
    assert_equal 0, Analytics::Compactor.new(today: TODAY).run
    assert_equal 1, DailyStat.count
    assert_equal before, DailyStat.find_by!(day: OLD).attributes
  end

  test "late raw rows for an already compacted day replace the aggregate (re-run safe), nothing is left behind" do
    seed_old_day
    Analytics::Compactor.new(today: TODAY).run
    visit!(OLD, "late")
    assert_equal 1, Analytics::Compactor.new(today: TODAY).run
    assert_equal 1, DailyStat.count
    assert_equal 0, Visit.count
  end

  test "retention boundary: exactly 90 days old stays raw, 91 days is compacted" do
    visit!(TODAY - 90, "edge")
    visit!(TODAY - 91, "old")
    assert_equal 1, Analytics::Compactor.new(today: TODAY).run
    assert_equal [ TODAY - 90 ], Visit.pluck(:day)
    assert_equal [ TODAY - 91 ], DailyStat.pluck(:day)
  end

  test "all-or-nothing: a failure while compacting leaves the raw rows untouched" do
    seed_old_day
    DailyStat.singleton_class.send(:define_method, :find_or_initialize_by) { |*| raise "boom" }
    begin
      assert_raises(RuntimeError) { Analytics::Compactor.new(today: TODAY).run }
    ensure
      DailyStat.singleton_class.send(:remove_method, :find_or_initialize_by)
    end
    assert_equal 3, Visit.count
    assert_equal 0, DailyStat.count
  end

  test "many old days (over one batch) and sources beyond the top 20 are folded into 'outros'" do
    40.times { |i| visit!(OLD - i, "v#{i}") }
    25.times { |i| visit!(OLD - 50, "s#{i}", source: "site#{format('%02d', i)}.com") }
    assert_equal 41, Analytics::Compactor.new(today: TODAY).run
    assert_equal 0, Visit.count
    stat = DailyStat.find_by!(day: OLD - 50)
    assert_equal 21, stat.sources.size
    assert_equal 5, stat.sources["outros"]
    assert_equal 25, stat.visits
  end

  test "opportunistic run: once per hour per process, guarded by an atomic marker, and never raises" do
    seed_old_day
    assert_equal 1, Analytics::Compactor.run_if_due(today: TODAY)
    assert_nil Analytics::Compactor.run_if_due(today: TODAY), "second call within the hour does nothing"
    Analytics::Compactor.last_check = nil
    assert_nil Analytics::Compactor.run_if_due(today: TODAY), "another process holds the hourly marker"
    RateLimiter::RateLimit.where(action: "once").update_all(expires_at: 1.minute.ago)
    seed_old_day
    Analytics::Compactor.last_check = nil
    assert_equal 1, Analytics::Compactor.run_if_due(today: TODAY)
  end

  test "a process that booted less than an hour ago (small monotonic clock) still runs the first compaction" do
    seed_old_day
    Analytics::Compactor.last_check = nil
    real = Process.method(:clock_gettime)
    Process.define_singleton_method(:clock_gettime) { |*| 120.0 }
    begin
      assert_equal 1, Analytics::Compactor.run_if_due(today: TODAY)
    ensure
      Process.define_singleton_method(:clock_gettime, real)
    end
  end

  test "rake stats:compact" do
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("stats:compact")
    seed_old_day
    travel_to Time.utc(2026, 10, 10, 15) do
      assert_output(/Compacted 1 day/) { Rake::Task["stats:compact"].reenable; Rake::Task["stats:compact"].invoke }
    end
    assert_equal 0, Visit.count
  end
end
