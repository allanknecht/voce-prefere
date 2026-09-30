require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    https! # the admin cookie is Secure, like in production
    @option = Option.create!(text: "Opção pendente", status: "pending")
  end

  def login_token
    get admin_login_path
    css_select("input[name=login_token]").first["value"]
  end

  def login!(secret: AdminSecret.value)
    post admin_login_path, params: { secret: secret, login_token: login_token }, headers: { "Origin" => "https://www.example.com" }
  end

  # Rails issues per-form tokens: take the one of the form that posts to `action`.
  def csrf_token_from(path, action:)
    get path
    css_select("form[action='#{action}'] input[name=authenticity_token]").first["value"]
  end

  # ---- login -------------------------------------------------------------------

  test "login page is a POST form and does not accept ?secret= in the URL" do
    get admin_login_path
    assert_select "form[method=post][action=?]", admin_login_path
    assert_select "input[type=password][name=secret]"

    get admin_index_path, params: { secret: AdminSecret.value }
    assert_redirected_to admin_login_path
  end

  test "wrong password is rejected and sets no authenticated session" do
    login!(secret: "nope")
    assert_response :unauthorized
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  test "correct password logs in" do
    login!
    assert_redirected_to admin_index_path
    follow_redirect!
    assert_response :success
    assert_match "Painel Admin", response.body
  end

  test "GET /admin/login sets no cookie and no session-based CSRF token" do
    get admin_login_path
    assert_response :success
    assert_nil response.headers["Set-Cookie"]
    assert_select "input[name=authenticity_token]", 0
    assert_select "input[name=login_token][value]", 1
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "failed logins (wrong password, bad token, throttled) set no cookie either" do
    login!(secret: "nope")
    assert_response :unauthorized
    assert_nil response.headers["Set-Cookie"]

    post admin_login_path, params: { secret: AdminSecret.value }
    assert_response :unprocessable_entity
    assert_nil response.headers["Set-Cookie"]
  end

  test "protected admin pages redirect anonymous visitors without a cookie" do
    get admin_index_path
    assert_redirected_to admin_login_path
    assert_nil response.headers["Set-Cookie"]
  end

  test "login without the form token is rejected" do
    post admin_login_path, params: { secret: AdminSecret.value }, headers: { "Origin" => "https://www.example.com" }
    assert_response :unprocessable_entity
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  test "login with a forged token is rejected" do
    post admin_login_path, params: { secret: AdminSecret.value, login_token: "forged" }, headers: { "Origin" => "https://www.example.com" }
    assert_response :unprocessable_entity
  end

  test "a public-form token cannot be replayed on the admin login (purpose-bound)" do
    get root_path
    public_token = css_select('meta[name="form-token"]').first["content"]
    post admin_login_path, params: { secret: AdminSecret.value, login_token: public_token }, headers: { "Origin" => "https://www.example.com" }
    assert_response :unprocessable_entity
  end

  test "login from another origin is rejected even with a valid token" do
    token = login_token
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: { "Origin" => "https://evil.example" }
    assert_response :unprocessable_entity
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token },
         headers: { "Origin" => "https://www.example.com", "Sec-Fetch-Site" => "cross-site" }
    assert_response :unprocessable_entity
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  # ---- same-origin evidence (Referrer-Policy: no-referrer => browsers send "Origin: null") ----

  def post_login(secret:, headers:, token: login_token)
    post admin_login_path, params: { secret: secret, login_token: token }, headers: headers
  end

  test "Origin: null + Sec-Fetch-Site: same-origin passes the origin check (wrong password => 401)" do
    post_login(secret: "nope", headers: { "Origin" => "null", "Sec-Fetch-Site" => "same-origin" })
    assert_response :unauthorized
    assert_nil response.headers["Set-Cookie"]
  end

  test "Origin: null + Sec-Fetch-Site: same-origin + correct password logs in and sets the admin cookie" do
    post_login(secret: AdminSecret.value, headers: { "Origin" => "null", "Sec-Fetch-Site" => "same-origin" })
    assert_redirected_to admin_index_path
    assert_match(/_voce_prefere_admin=/, Array(response.headers["Set-Cookie"]).join)
  end

  test "Sec-Fetch-Site same-origin works without any Origin/Referer, and whatever the scheme the proxy shows" do
    post_login(secret: "nope", headers: { "Sec-Fetch-Site" => "same-origin" })
    assert_response :unauthorized
    post_login(secret: "nope", headers: { "Sec-Fetch-Site" => "same-origin", "X-Forwarded-Proto" => "https" })
    assert_response :unauthorized
  end

  test "cross-site, same-site, none and unknown Sec-Fetch-Site values are rejected (even with a matching Origin and valid token)" do
    %w[cross-site same-site none bogus].each do |value|
      post_login(secret: AdminSecret.value, headers: { "Origin" => "https://www.example.com", "Sec-Fetch-Site" => value })
      assert_response :unprocessable_entity, "Sec-Fetch-Site: #{value} must be rejected"
      assert_nil response.headers["Set-Cookie"]
    end
  end

  test "without Sec-Fetch-Site, a matching Origin host passes (scheme is not compared)" do
    post_login(secret: "nope", headers: { "Origin" => "https://www.example.com" })
    assert_response :unauthorized
    post_login(secret: "nope", headers: { "Origin" => "http://www.example.com" })
    assert_response :unauthorized
  end

  test "without Sec-Fetch-Site, Origin: null, a foreign Origin or garbage are rejected" do
    [ "null", "https://evil.example", "https://www.example.com.evil.example", "not a url", "" ].each do |origin|
      post_login(secret: AdminSecret.value, headers: { "Origin" => origin })
      assert_response :unprocessable_entity, "Origin #{origin.inspect} must be rejected"
    end
  end

  test "without Sec-Fetch-Site and with Origin: null, only a same-host Referer can save it" do
    post_login(secret: "nope", headers: { "Origin" => "null", "Referer" => "https://www.example.com/admin/login" })
    assert_response :unprocessable_entity # Origin present (null) wins: no fallback to Referer
  end

  test "a valid token is still required when Sec-Fetch-Site is same-origin" do
    post admin_login_path, params: { secret: AdminSecret.value, login_token: "forged" }, headers: { "Sec-Fetch-Site" => "same-origin" }
    assert_response :unprocessable_entity
    post admin_login_path, params: { secret: AdminSecret.value }, headers: { "Sec-Fetch-Site" => "same-origin" }
    assert_response :unprocessable_entity
  end

  test "login without Origin/Referer is rejected" do
    post admin_login_path, params: { secret: AdminSecret.value, login_token: login_token }
    assert_response :unprocessable_entity
  end

  test "login accepts a same-origin Referer when Origin is absent" do
    post admin_login_path, params: { secret: AdminSecret.value, login_token: login_token }, headers: { "Referer" => "https://www.example.com/admin/login" }
    assert_redirected_to admin_index_path
  end

  test "an expired login token is rejected" do
    token = login_token
    travel 2.hours do
      post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: { "Origin" => "https://www.example.com" }
      assert_response :unprocessable_entity
    end
  end

  test "login is rate limited" do
    RateLimiter::RateLimit.delete_all
    6.times { login!(secret: "wrong") }
    assert_response :too_many_requests
  end

  # ---- cookie flags --------------------------------------------------------------

  test "admin session cookie is Secure, HttpOnly, SameSite=Strict and scoped to /admin" do
    post admin_login_path, params: { secret: AdminSecret.value, login_token: login_token }, headers: { "Origin" => "https://www.example.com" }

    cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/_voce_prefere_admin=/, cookie)
    assert_match(/;\s*path=\/admin(;|$)/i, cookie)
    assert_match(/;\s*secure/i, cookie)
    assert_match(/;\s*httponly/i, cookie)
    assert_match(/;\s*samesite=strict/i, cookie)
    assert_match(/;\s*expires=/i, cookie)
  end

  test "public pages never set a cookie" do
    5.times { |i| Option.create!(text: "Opção pública #{i}", status: "approved") }
    pair = PairGenerator.random_pair
    [ root_path, pages_about_path, pairs_day_path, pairs_controversial_path, admin_login_path, "/up",
      pair_path(PairGenerator.hash_for(pair[0], pair[1])), pair_path("nonexistent"), "/pairs/day/../nope" ].each do |path|
      get path
      assert_nil response.headers["Set-Cookie"], "#{path} set a cookie"
    end
  end

  # ---- CSRF on approve / reject -----------------------------------------------------

  test "approve without CSRF token is rejected and changes nothing" do
    login!
    post admin_approve_path(@option)
    assert_response :unprocessable_entity
    assert_equal "pending", @option.reload.status
  end

  test "reject without CSRF token is rejected and changes nothing" do
    login!
    post admin_reject_path(@option)
    assert_response :unprocessable_entity
    assert_equal "pending", @option.reload.status
  end

  test "approve and reject work with the CSRF token rendered in the admin page" do
    login!
    token = csrf_token_from(admin_index_path, action: admin_approve_path(@option))
    post admin_approve_path(@option), params: { authenticity_token: token }
    assert_redirected_to admin_index_path
    assert_equal "approved", @option.reload.status

    other = Option.create!(text: "Outra pendente", status: "pending")
    token = csrf_token_from(admin_index_path, action: admin_reject_path(other))
    post admin_reject_path(other), params: { authenticity_token: token }
    assert_equal "rejected", other.reload.status
  end

  test "approve requires authentication" do
    post admin_approve_path(@option)
    assert_includes [ 302, 422 ], response.status
    assert_equal "pending", @option.reload.status
  end

  test "logout clears the session" do
    login!
    token = csrf_token_from(admin_index_path, action: admin_logout_path)
    delete admin_logout_path, params: { authenticity_token: token }
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  test "expired admin session is refused" do
    login!
    travel 2.hours do
      get admin_index_path
      assert_redirected_to admin_login_path
    end
  end

  # ---- ADMIN_SECRET ------------------------------------------------------------------

  test "no default secret outside of development/test conventions: value is nil in production without env" do
    out, ok = ProductionBoot.attempt('puts "SECRET=#{AdminSecret.value.inspect}"', env: { "SECRET_KEY_BASE_DUMMY" => "1" })
    assert ok, out
    assert_includes out, "SECRET=nil"
  end

  test "production refuses to boot when ADMIN_SECRET is unset" do
    out, ok = ProductionBoot.attempt("puts :booted")
    refute ok
    assert_match(/ADMIN_SECRET must be set/, out)
    refute_match(/booted/, out)
  end

  test "production refuses to boot with the placeholder or a weak ADMIN_SECRET" do
    [ "change-me-in-production", "", "   ", "short" ].each do |bad|
      out, ok = ProductionBoot.attempt("puts :booted", env: { "ADMIN_SECRET" => bad })
      refute ok, "booted with ADMIN_SECRET=#{bad.inspect}"
      assert_match(/ADMIN_SECRET must be set/, out)
    end
  end

  test "production boots with a strong ADMIN_SECRET and SECRET_KEY_BASE only (no credentials file, no master key)" do
    refute File.exist?(Rails.root.join("config/credentials.yml.enc"))
    out, ok = ProductionBoot.attempt('puts "booted #{Rails.application.secret_key_base.length > 30}"',
                                     env: { "ADMIN_SECRET" => SecureRandom.hex(16) })
    assert ok, out
    assert_match(/booted true/, out)
  end

  test "production does not fall back to the placeholder when comparing" do
    out, ok = ProductionBoot.attempt('puts "MATCH=#{AdminSecret.matches?("change-me-in-production")}/#{AdminSecret.matches?("")}"',
                                     env: { "SECRET_KEY_BASE_DUMMY" => "1" })
    assert ok, out
    assert_includes out, "MATCH=false/false"
  end
end
