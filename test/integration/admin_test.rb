require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    https! # the admin cookie is Secure, like in production
    @option = Option.create!(text: "Opção pendente", status: "pending")
  end

  def login!(secret: AdminSecret.value)
    get admin_login_path
    token = css_select("input[name=authenticity_token]").first["value"]
    post admin_login_path, params: { secret: secret, authenticity_token: token }
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

  test "login without CSRF token is rejected" do
    post admin_login_path, params: { secret: AdminSecret.value }
    assert_response :unprocessable_entity
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  test "login is rate limited" do
    RateLimiter::RateLimit.delete_all
    6.times { login!(secret: "wrong") }
    assert_response :too_many_requests
  end

  # ---- cookie flags --------------------------------------------------------------

  test "admin session cookie is Secure, HttpOnly, SameSite=Strict and scoped to /admin" do
    get admin_login_path
    token = css_select("input[name=authenticity_token]").first["value"]
    post admin_login_path, params: { secret: AdminSecret.value, authenticity_token: token }

    cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/_voce_prefere_admin=/, cookie)
    assert_match(/;\s*path=\/admin(;|$)/i, cookie)
    assert_match(/;\s*secure/i, cookie)
    assert_match(/;\s*httponly/i, cookie)
    assert_match(/;\s*samesite=strict/i, cookie)
    assert_match(/;\s*expires=/i, cookie)
  end

  test "the login page cookie (CSRF session) has the same flags" do
    get admin_login_path
    cookie = Array(response.headers["Set-Cookie"]).join("\n")
    assert_match(/path=\/admin/i, cookie)
    assert_match(/secure/i, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=strict/i, cookie)
  end

  test "public pages never set a cookie" do
    [ root_path, pages_about_path, pairs_day_path, pairs_controversial_path ].each do |path|
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
