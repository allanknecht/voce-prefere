require "test_helper"

class AnalyticsTest < ActionDispatch::IntegrationTest
  PHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze
  DESKTOP = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36".freeze
  TABLET = "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1".freeze
  SAME_ORIGIN = { "CONTENT_TYPE" => "application/json", "Accept" => "application/json", "Sec-Fetch-Site" => "same-origin" }.freeze

  setup do
    RateLimiter::RateLimit.delete_all
    [ Visit, AnalyticsEvent, DailyStat ].each(&:delete_all)
    @a = Option.create!(text: "Boa A", status: "approved", category: "good")
    @b = Option.create!(text: "Boa B", status: "approved", category: "good")
    @pair = PairGenerator.hash_for(@a, @b)
  end

  def beacon(body, ua: PHONE, ip: "10.1.2.3", headers: {})
    post analytics_beacon_path, params: body.to_json, headers: SAME_ORIGIN.merge("User-Agent" => ua).merge(headers), env: { "REMOTE_ADDR" => ip }
  end

  def visit(extra = {}, **opts)
    beacon({ kind: "visit", screen: "home" }.merge(extra), **opts)
  end

  def vote(option = @a, ua: PHONE, ip: "10.1.2.3")
    headers = public_post_headers.merge("User-Agent" => ua)
    post votes_path, params: { option_id: option.id, pair_hash: @pair }.to_json, headers: headers, env: { "REMOTE_ADDR" => ip }
  end

  # ---- bots, opt-out ---------------------------------------------------------------------------

  test "known bots, crawlers, monitors and empty user agents are never recorded" do
    bots = [ "Googlebot/2.1 (+http://www.google.com/bot.html)", "Mozilla/5.0 (compatible; bingbot/2.0)", "facebookexternalhit/1.1",
             "WhatsApp/2.23.20.0 A", "Slackbot-LinkExpanding 1.0", "Twitterbot/1.0", "curl/8.4.0", "python-requests/2.31.0",
             "Mozilla/5.0 HeadlessChrome/130.0.0.0 Safari/537.36", "GitHub-Actions keepalive", "UptimeRobot/2.0", "Go-http-client/2.0",
             "Mozilla/5.0 (compatible; AhrefsBot/7.0)", "Wget/1.21", "", "x", "node-fetch/1.0 (+https://github.com/node-fetch)" ]
    bots.each { |ua| visit(ua: ua) }
    visit(ua: nil.to_s)
    assert_equal 0, Visit.count
    bots.each { |ua| assert Analytics.bot?(ua), ua.inspect }
    [ PHONE, DESKTOP, TABLET ].each { |ua| refute Analytics.bot?(ua), ua }
    visit(ua: DESKTOP)
    assert_equal 1, Visit.count
  end

  test "Sec-GPC: 1 and DNT: 1 are honoured (nothing recorded), 0 is not an opt-out" do
    visit({}, headers: { "Sec-GPC" => "1" })
    visit({}, headers: { "DNT" => "1" })
    vote_headers = public_post_headers.merge("User-Agent" => PHONE, "Sec-GPC" => "1")
    post votes_path, params: { option_id: @a.id, pair_hash: @pair }.to_json, headers: vote_headers
    assert_response :success
    assert_equal [ 0, 0, 1 ], [ Visit.count, AnalyticsEvent.count, Vote.count ]
    visit({}, headers: { "DNT" => "0", "Sec-GPC" => "0" })
    assert_equal 1, Visit.count
  end

  test "the health check, assets and the admin area are never recorded" do
    get "/up", headers: { "User-Agent" => PHONE }
    get "/admin/login", headers: { "User-Agent" => PHONE }
    get "/assets/tailwind.css", headers: { "User-Agent" => PHONE }
    assert_equal 0, Visit.count
    get root_path, headers: { "User-Agent" => PHONE }
    assert_select "body[data-screen=home]"
    get admin_login_path
    assert_select "body[data-screen]", 0
  end

  # ---- visitor hash, no personal data --------------------------------------------------------------

  test "visitor hash: daily rotating, same within a day, differs per ip/ua, never contains the ip or the ua" do
    d1 = Date.new(2026, 10, 1)
    d2 = Date.new(2026, 10, 2)
    h = Analytics.visitor_hash("1.2.3.4", PHONE, d1)
    assert_equal h, Analytics.visitor_hash("1.2.3.4", PHONE, d1)
    refute_equal h, Analytics.visitor_hash("1.2.3.4", PHONE, d2), "changes every day"
    refute_equal h, Analytics.visitor_hash("1.2.3.5", PHONE, d1)
    refute_equal h, Analytics.visitor_hash("1.2.3.4", DESKTOP, d1)
    assert_match(/\A\h{16}\z/, h)
    refute_includes h, "1.2.3.4"
    refute_equal Analytics.daily_salt(d1), Analytics.daily_salt(d2)
  end

  test "the salt is derived from the app secret (another secret = other hashes)" do
    d = Date.new(2026, 10, 1)
    a = Analytics.visitor_hash("1.2.3.4", PHONE, d)
    Analytics.instance_variable_set(:@base_key, OpenSSL::HMAC.digest("SHA256", "other", "x"))
    refute_equal a, Analytics.visitor_hash("1.2.3.4", PHONE, d)
  ensure
    Analytics.instance_variable_set(:@base_key, nil)
  end

  test "schema: no ip, user agent, url, referrer path or other personal column in any analytics table" do
    forbidden = /\A(ip|ip_address|remote_ip|user_agent|ua|url|path|referrer|referer|query|text|email|cookie|session|fingerprint)\z/
    { "visits" => Visit, "events" => AnalyticsEvent, "daily_stats" => DailyStat }.each do |table, model|
      names = model.column_names
      names.each { |name| refute_match(forbidden, name, "#{table}.#{name}") }
    end
    assert_equal %w[day device hour id occurred_at pair_hash returning_visit screen source via_share visitor_hash], Visit.column_names.sort
    assert_equal %w[day device hour id kind occurred_at option_id pair_hash visitor_hash], AnalyticsEvent.column_names.sort
    assert_includes ActiveRecord::Base.connection.indexes(:visits).map(&:columns), [ "day", "visitor_hash" ]
    assert_includes ActiveRecord::Base.connection.indexes(:visits).map(&:columns), [ "occurred_at" ]
  end

  test "a stored visit has neither the ip nor the user agent anywhere in its row" do
    visit({ referrer: "www.google.com", pair_hash: "1-2", screen: "pair" }, ua: PHONE, ip: "198.51.100.77")
    row = Visit.last.attributes.values.map(&:to_s).join(" | ")
    refute_includes row, "198.51.100.77"
    refute_includes row, "iPhone"
    refute_includes row, "Safari"
    assert_equal [ "mobile", "pair", "google.com", "1-2" ], [ Visit.last.device, Visit.last.screen, Visit.last.source, Visit.last.pair_hash ]
  end

  test "no cookie on any public response, the beacon included, and nothing about the ip in the log" do
    [ root_path, pairs_day_path, pages_about_path, pairs_controversial_path ].each do |path|
      get path, headers: { "User-Agent" => PHONE }
      assert_nil response.headers["Set-Cookie"], path
    end
    visit
    assert_response :no_content
    assert_nil response.headers["Set-Cookie"]
    vote
    assert_nil response.headers["Set-Cookie"]
  end

  # ---- sanitizing ---------------------------------------------------------------------------------------

  test "referrer: registrable domain only, never path/query; junk and javascript: are 'direto'" do
    s = ->(v, own = "voceprefere.example") { Analytics.referrer_source(v, own_host: own) }
    assert_equal "google.com", s.("https://www.google.com/search?q=secret+words")
    assert_equal "instagram.com", s.("https://l.instagram.com/?u=http%3A%2F%2Fx&e=abc")
    assert_equal "google.com", s.("www.google.com")
    assert_equal "t.co", s.("t.co")
    assert_equal "uol.com.br", s.("https://noticias.uol.com.br/a/b?c=d")
    assert_equal "bbc.co.uk", s.("https://www.bbc.co.uk/")
    assert_equal "direto", s.("")
    assert_equal "direto", s.(nil)
    assert_equal "direto", s.("javascript:alert(1)")
    assert_equal "direto", s.("data:text/html,<script>")
    assert_equal "direto", s.("not a url at all")
    assert_equal "direto", s.("https://voceprefere.example/pairs/1-2")
    assert_equal "direto", s.("https://www.voceprefere.example/")
    assert_equal "direto", s.("x" * 500)
    assert_equal "outro", s.("ftp://example.org/x")
    assert_equal "outro", s.("http://10.0.0.1/admin")
    assert_equal "direto", s.("https://evil..com/<script>")
    %w[google.com t.co uol.com.br].each { |d| refute_match(%r{[/?#:]}, s.("https://sub.#{d}/path?x=1#f")) }
  end

  test "source tag (?s= / ?utm_source=): only a short [a-z0-9_-] token survives" do
    assert_equal "whatsapp", Analytics.source_tag("WhatsApp")
    assert_equal "insta_story-1", Analytics.source_tag("insta_story-1")
    assert_nil Analytics.source_tag("<script>alert(1)</script>")
    assert_nil Analytics.source_tag("a b")
    assert_nil Analytics.source_tag("x" * 25)
    assert_nil Analytics.source_tag("")
    assert_nil Analytics.source_tag("ação")
    visit({ tag: "WhatsApp", referrer: "www.google.com" })
    assert_equal "whatsapp", Visit.last.source
    visit({ tag: "<b>x</b>", referrer: "www.google.com" })
    assert_equal "google.com", Visit.last.source
  end

  test "device from the user agent: mobile / tablet / desktop" do
    assert_equal "mobile", Analytics.device(PHONE)
    assert_equal "mobile", Analytics.device("Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36")
    assert_equal "tablet", Analytics.device(TABLET)
    assert_equal "tablet", Analytics.device("Mozilla/5.0 (Linux; Android 12; SM-T500) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36")
    assert_equal "desktop", Analytics.device(DESKTOP)
    assert_equal "desktop", Analytics.device("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15")
  end

  test "screens are whitelisted, the pair hash only on pair screens and only if well formed" do
    visit({ screen: "pair", pair_hash: @pair })
    assert_equal [ "pair", @pair ], [ Visit.last.screen, Visit.last.pair_hash ]
    visit({ screen: "home", pair_hash: @pair })
    assert_nil Visit.last.pair_hash
    visit({ screen: "pair", pair_hash: "../../etc/passwd" })
    assert_nil Visit.last.pair_hash
    visit({ screen: "/admin/secret?x=1" })
    assert_equal "other", Visit.last.screen
    %w[home pair results day controversial about].each { |sc| visit({ screen: sc }); assert_equal sc, Visit.last.screen }
  end

  # ---- visits: returning / via share ------------------------------------------------------------------------

  test "returning and via_share come from the client booleans; a shared-link visit also creates an event" do
    visit({ returning: true, via_share: true, screen: "pair", pair_hash: @pair })
    v = Visit.last
    assert_equal [ true, true ], [ v.returning_visit, v.via_share ]
    assert_equal [ "shared_link_visit" ], AnalyticsEvent.pluck(:kind)
    visit({ returning: "yes please", via_share: "junk" })
    assert_equal [ false, false ], [ Visit.last.returning_visit, Visit.last.via_share ]
    assert_equal 1, AnalyticsEvent.count
    visit
    assert_equal false, Visit.last.returning_visit
  end

  test "day and hour are in America/Sao_Paulo" do
    travel_to Time.utc(2026, 10, 2, 1, 30) do # 22:30 on Oct 1 in Brasília (UTC-3)
      visit
      assert_equal [ Date.new(2026, 10, 1), 22 ], [ Visit.last.day, Visit.last.hour ]
    end
  end

  # ---- events ----------------------------------------------------------------------------------------------------

  test "vote, submit and report are recorded as events after success, with no text" do
    vote
    assert_equal [ "vote" ], AnalyticsEvent.pluck(:kind)
    assert_equal [ @pair, @a.id ], [ AnalyticsEvent.last.pair_hash, AnalyticsEvent.last.option_id ]
    post options_path, params: { text: "Texto que não deve ser guardado", category: "good" }.to_json, headers: public_post_headers.merge("User-Agent" => PHONE)
    assert_response :success
    assert_equal "submit_option", AnalyticsEvent.last.kind
    assert_nil AnalyticsEvent.last.option_id
    assert_nil AnalyticsEvent.last.pair_hash
    post report_option_path(@a), headers: public_post_headers.merge("User-Agent" => PHONE)
    assert_equal "report", AnalyticsEvent.last.kind
    assert_equal @a.id, AnalyticsEvent.last.option_id
    refute_includes AnalyticsEvent.all.map(&:attributes).to_s, "Texto que não"
  end

  test "failed or duplicate actions record nothing" do
    post votes_path, params: { option_id: @a.id, pair_hash: "bad" }.to_json, headers: public_post_headers.merge("User-Agent" => PHONE)
    assert_response :unprocessable_entity
    post options_path, params: { text: "", category: "good" }.to_json, headers: public_post_headers.merge("User-Agent" => PHONE)
    vote
    vote # idempotent duplicate within 10 s: not counted, not recorded again
    assert_equal 1, AnalyticsEvent.where(kind: "vote").count
    assert_equal 1, Vote.count
  end

  test "an analytics failure never breaks the request" do
    original = AnalyticsEvent.method(:create!)
    AnalyticsEvent.define_singleton_method(:create!) { |*| raise ActiveRecord::StatementInvalid, "analytics db down" }
    begin
      vote
      assert_response :success
      assert_equal 1, Vote.count
      post options_path, params: { text: "Funciona mesmo assim", category: "good" }.to_json, headers: public_post_headers.merge("User-Agent" => PHONE)
      assert_response :success
      post report_option_path(@a), headers: public_post_headers.merge("User-Agent" => PHONE)
      assert_response :success
    ensure
      AnalyticsEvent.define_singleton_method(:create!, original)
    end
    Visit.define_singleton_method(:create!) { |*| raise "boom" }
    begin
      visit
      assert_response :no_content
    ensure
      Visit.singleton_class.send(:remove_method, :create!)
    end
  end

  test "with Puma's rack.after_reply the insert runs after the response and adds no query to the request itself" do
    after = []
    headers = public_post_headers.merge("User-Agent" => PHONE)
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    get root_path
    PairGenerator.new.send(:approved_options)
    RateLimiter.last_cleanup = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    queries = count_queries { post votes_path, params: { option_id: @a.id, pair_hash: @pair }.to_json, headers: headers, env: { "rack.after_reply" => after } }
    assert_response :success
    assert_equal 0, AnalyticsEvent.count, "nothing inserted before the response was sent"
    assert_equal 1, after.size
    assert_operator queries.size, :<=, 5, queries.join("\n")
    insert = count_queries { after.each(&:call) }
    assert_equal 1, insert.grep(/INSERT INTO "events"/).size
    assert_equal 1, AnalyticsEvent.count
  ensure
    Rails.cache = original_cache
  end

  # ---- beacon endpoint -------------------------------------------------------------------------------------------

  test "beacon: same-origin required (cross-site and missing headers are refused)" do
    post analytics_beacon_path, params: { kind: "visit", screen: "home" }.to_json, headers: SAME_ORIGIN.merge("User-Agent" => PHONE, "Sec-Fetch-Site" => "cross-site")
    assert_response :forbidden
    post analytics_beacon_path, params: { kind: "visit" }.to_json, headers: { "CONTENT_TYPE" => "application/json", "User-Agent" => PHONE }
    assert_response :forbidden
    post analytics_beacon_path, params: { kind: "visit", screen: "home" }.to_json, headers: { "CONTENT_TYPE" => "application/json", "Origin" => "http://evil.example", "User-Agent" => PHONE }
    assert_response :forbidden
    assert_equal 0, Visit.count
    get analytics_beacon_path rescue nil
    visit
    assert_response :no_content
    assert_equal 1, Visit.count
  end

  test "beacon: only whitelisted kinds (visit, share_click); server-only kinds cannot be forged" do
    %w[vote submit_option report shared_link_visit hack].each do |kind|
      beacon({ kind: kind })
      assert_response :unprocessable_entity, kind
    end
    assert_equal 0, AnalyticsEvent.count
    beacon({ kind: "share_click", pair_hash: @pair })
    assert_response :no_content
    assert_equal [ "share_click", @pair ], [ AnalyticsEvent.last.kind, AnalyticsEvent.last.pair_hash ]
  end

  test "beacon: rate limited per hashed ip" do
    RateLimiter::LIMITS[:beacon] # exists
    key = RateLimiter.new("10.1.2.3", :beacon)
    RateLimiter::RateLimit.upsert({ hashed_key: key.send(:hashed_key), action: "beacon", count: 600, expires_at: 1.hour.from_now, created_at: Time.current, updated_at: Time.current }, unique_by: :hashed_key)
    visit
    assert_response :too_many_requests
    assert_equal 0, Visit.count
    visit({}, ip: "10.9.9.9")
    assert_response :no_content
  end

  test "the script sends the beacon only on pages with data-screen, and only the whitelisted fields" do
    js = Rails.root.join("app/assets/javascripts/application.js").read
    assert_match(%r{fetch\("/m"}, js)
    assert_match(/c=1/, js)
    assert_match(/last_visit/, js)
    assert_no_match(/navigator\.userAgent|document\.cookie|\bscreen\.width\b/, js)
  end
end
