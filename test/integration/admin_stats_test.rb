require "test_helper"

class AdminStatsTest < ActionDispatch::IntegrationTest
  TODAY = Date.new(2026, 10, 10)

  setup do
    https!
    RateLimiter::RateLimit.delete_all
    [ Visit, AnalyticsEvent, DailyStat, Vote ].each(&:delete_all)
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @a = Option.create!(text: "Voar", status: "approved", category: "good")
    @b = Option.create!(text: "Ser invisível", status: "approved", category: "good")
    @pair = PairGenerator.hash_for(@a, @b)
    travel_to Time.utc(2026, 10, 10, 15, 0) # noon in Brasília
  end

  teardown do
    travel_back
    Rails.cache = Rails.application.config.cache_store == :null_store ? ActiveSupport::Cache::NullStore.new : Rails.cache
  end

  def login!
    get admin_login_path
    token = css_select("input[name=login_token]").first["value"]
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: { "Sec-Fetch-Site" => "same-origin" }
  end

  def visit!(day: TODAY, hour: 12, visitor: "aaaa", returning: false, source: "direto", via_share: false, device: "mobile", screen: "home")
    Visit.create!(occurred_at: Time.utc(day.year, day.month, day.day) + (hour + 3).hours, day: day, hour: hour, screen: screen, device: device,
                  source: source, via_share: via_share, returning_visit: returning, visitor_hash: visitor)
  end

  def event!(kind, day: TODAY, hour: 12, visitor: "aaaa", pair: nil, option: nil)
    AnalyticsEvent.create!(occurred_at: Time.utc(day.year, day.month, day.day) + (hour + 3).hours, day: day, hour: hour, kind: kind,
                           pair_hash: pair, option_id: option, device: "mobile", visitor_hash: visitor)
  end

  # ---- access ---------------------------------------------------------------------------------------

  test "stats need the admin session, are no-store and linked from the dashboard" do
    get admin_stats_path
    assert_redirected_to admin_login_path
    login!
    get admin_stats_path
    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    get admin_index_path
    assert_select "a[href=?]", admin_stats_path, text: /Estatísticas/
    assert_select "script:not([src])", 0
    assert_select "[style]", 0
  end

  test "period selector: 7 / 30 / 90, default 30, junk falls back to 30" do
    login!
    get admin_stats_path
    assert_select "a[aria-current=page]", text: "30 dias"
    [ 7, 30, 90 ].each do |days|
      get admin_stats_path(dias: days)
      assert_select "a[aria-current=page]", text: "#{days} dias"
    end
    get admin_stats_path(dias: "9999")
    assert_select "a[aria-current=page]", text: "30 dias"
    assert_equal 30, Analytics::Report.period("DROP TABLE")
  end

  test "the page is server rendered with CSS bars (width classes), no inline styles, honest note about daily visitors" do
    visit!
    login!
    get admin_stats_path
    assert_select ".stat-bar", minimum: 1
    assert_select "[class*=bar-w-]", minimum: 1
    assert_match(/mesma pessoa em dois dias conta duas vezes/, response.body)
    assert_match(/Sem cookies, sem IP e sem user agent/, response.body)
    assert_nil response.headers["Content-Security-Policy"].to_s[/unsafe-inline/]
  end

  # ---- computations --------------------------------------------------------------------------------

  test "visits, unique visitors per day, returning share, sources, devices" do
    visit!(visitor: "a1")
    visit!(visitor: "a1", screen: "pair")
    visit!(visitor: "b2", returning: true, source: "google.com", device: "desktop")
    visit!(visitor: "c3", via_share: true, source: "whatsapp")
    visit!(day: TODAY - 1, visitor: "a1", returning: true, source: "google.com")
    r = Analytics::Report.new(days: 7, today: TODAY)
    assert_equal 5, r.visits
    assert_equal 4, r.unique_visitors # a1 counts once on each day: 3 today + 1 yesterday
    assert_equal [ 4, 3 ], [ r.day(TODAY)[:visits], r.day(TODAY)[:unique_visitors] ]
    assert_equal 40.0, r.returning_share
    assert_equal [ [ "direto", 2 ], [ "google.com", 2 ], [ "whatsapp", 1 ] ], r.sources
    assert_equal 1, r.total(:via_share_visits)
    assert_equal({ "Celular" => 4, "Computador" => 1, "Tablet" => 0 }, r.devices)
    assert_equal 0, r.day(TODAY - 5)[:visits]
  end

  test "votes per day, votes per voter, polls per voter-day, funnel, shares, submits, reports" do
    4.times { visit!(visitor: "v1") }
    visit!(visitor: "v2")
    visit!(visitor: "v3")
    visit!(visitor: "v4")
    other = PairGenerator.hash_for(@a, Option.create!(text: "Terceira", status: "approved", category: "good"))
    3.times { event!("vote", visitor: "v1", pair: @pair) } # same poll thrice: counts one poll
    event!("vote", visitor: "v1", pair: other)
    event!("vote", visitor: "v2", pair: @pair)
    event!("submit_option", visitor: "v2")
    event!("share_click", visitor: "v2")
    event!("share_click", visitor: "v2")
    event!("report", visitor: "v3", option: @a.id)
    event!("vote", day: TODAY - 2, visitor: "v9", pair: @pair)
    r = Analytics::Report.new(days: 30, today: TODAY)
    assert_equal [ 5, 2, 1 ], [ r.day(TODAY)[:votes], r.day(TODAY)[:voting_visitors], r.day(TODAY - 2)[:votes] ]
    assert_equal 6, r.votes
    assert_equal 2.0, r.votes_per_voter # 6 votes over 3 voter-days
    # polls: v1 -> 2, v2 -> 1, v9 -> 1 = 4 over 3 voter-days
    assert_equal (4 / 3.0).round(2), r.polls_per_voter
    assert_equal [ [ "Visitou", 4 ], [ "Votou", 3 ], [ "Enviou opção", 1 ], [ "Compartilhou", 1 ] ], r.funnel
    assert_equal [ 2, 1, 1 ], [ r.total(:shares), r.total(:submits), r.total(:reports) ]
    assert_equal 1, r.total(:sharing_visitors)
  end

  test "peak hours are hours of America/Sao_Paulo" do
    travel_to Time.utc(2026, 10, 10, 1, 30) do # 22:30 of Oct 9 in Brasília
      get root_path, headers: { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36" }
      post analytics_beacon_path, params: { kind: "visit", screen: "home" }.to_json,
                                  headers: { "CONTENT_TYPE" => "application/json", "Sec-Fetch-Site" => "same-origin",
                                             "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36" }
    end
    assert_equal [ Date.new(2026, 10, 9), 22 ], [ Visit.last.day, Visit.last.hour ]
    visit!(hour: 9)
    visit!(hour: 9, visitor: "z")
    visit!(hour: 22)
    hours = Analytics::Report.new(days: 7, today: TODAY).hours
    assert_equal 24, hours.size
    assert_equal [ 2, 2 ], [ hours[9], hours[22] ]
    assert_equal 4, hours.sum
  end

  test "most voted and most controversial polls show the option texts to the admin" do
    5.times { Vote.create!(option: @a, pair_hash: @pair) }
    6.times { Vote.create!(option: @b, pair_hash: @pair) }
    c = Option.create!(text: "Teletransporte", status: "approved", category: "good")
    pair2 = PairGenerator.hash_for(@a, c)
    2.times { Vote.create!(option: c, pair_hash: pair2) }
    r = Analytics::Report.new(days: 7, today: TODAY)
    assert_equal [ @pair, pair2 ], r.top_polls.map { |p| p[:pair_hash] }
    assert_equal 11, r.top_polls.first[:votes]
    login!
    get admin_stats_path(dias: 7)
    assert_match(/Voar × Ser invisível/, response.body)
    assert_match(/11 votos/, response.body)
    assert_match(/Voar × Teletransporte/, response.body)
    assert_match(/2 votos/, response.body)
    assert_no_match(/\b1 votos\b/, response.body)
    assert_match(/Voar|Ser invisível/, response.body[/Enquetes mais polêmicas.*?<\/ol>/m].to_s)
  end

  test "an empty period renders fine" do
    login!
    get admin_stats_path
    assert_response :success
    assert_match(/Ainda não há dados neste período/, response.body)
  end

  test "older days come from daily_stats, recent days from raw rows (raw wins on overlap)" do
    DailyStat.create!(day: TODAY - 60, visits: 10, unique_visitors: 6, returning_visits: 2, votes: 7, voting_visitors: 3, polls_voted: 4,
                      mobile_visits: 8, desktop_visits: 2, sources: { "google.com" => 4, "direto" => 6 }, hours: Array.new(24) { |h| h == 10 ? 10 : 0 })
    visit!(visitor: "n1")
    r = Analytics::Report.new(days: 90, today: TODAY)
    assert_equal 11, r.visits
    assert_equal [ 6, 10 ], [ r.day(TODAY - 60)[:unique_visitors], r.day(TODAY - 60)[:visits] ]
    assert_equal [ "direto", 7 ], r.sources.first
    assert_equal 10, r.hours[10]
    assert_equal 7, r.votes
    assert_equal 0, Analytics::Report.new(days: 30, today: TODAY).total(:votes), "the 30 day window does not include day-60"
  end
end
