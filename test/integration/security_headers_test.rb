require "test_helper"

class SecurityHeadersTest < ActionDispatch::IntegrationTest
  test "public page sends a real CSP without unsafe-inline / unsafe-eval / third parties" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "no Content-Security-Policy header"

    directives = csp.split(";").map(&:strip).to_h { |d| d.split(" ", 2).then { |k, v| [ k, v.to_s ] } }
    assert_equal "'none'", directives["default-src"]
    assert_equal "'self'", directives["script-src"]
    assert_equal "'self'", directives["style-src"]
    assert_equal "'none'", directives["object-src"]
    assert_equal "'none'", directives["frame-ancestors"]
    assert_equal "'self'", directives["base-uri"]
    assert_equal "'self'", directives["form-action"]
    refute_match(/unsafe-inline|unsafe-eval/, csp)
    refute_match(/cloudflare|https:\/\/|http:\/\//, csp, "no third-party origin may be allowed (Turnstile is not integrated)")
  end

  test "other security headers are real HTTP headers" do
    get root_path
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_match(/geolocation=\(\)/, response.headers["Permissions-Policy"])
    assert_match(/camera=\(\)/, response.headers["Permissions-Policy"])
    assert_match(/microphone=\(\)/, response.headers["Permissions-Policy"])
  end

  test "pages have no inline script/style and no http-equiv meta tags" do
    5.times { |i| Option.create!(text: "Opção número #{i}", status: "approved") }
    [ root_path, pages_about_path, pairs_day_path, pairs_controversial_path ].each do |path|
      get path
      assert_response :success, path
      assert_select "script:not([src])", 0, "inline <script> on #{path}"
      assert_select "[style]", 0, "inline style attribute on #{path}"
      assert_select "style", 0, "inline <style> on #{path}"
      assert_select "[onclick], [onchange], [onsubmit], [onload]", 0, "inline event handler on #{path}"
      assert_select "meta[http-equiv]", 0, "http-equiv meta on #{path}"
      assert_select "script[src]" do |scripts|
        scripts.each { |s| assert s["src"].start_with?("/assets/"), "external script #{s['src']}" }
      end
    end
  end

  test "admin pages have no inline scripts either" do
    https!
    get admin_login_path
    post admin_login_path, params: { secret: AdminSecret.value, login_token: css_select("input[name=login_token]").first["value"] },
         headers: { "Origin" => "https://www.example.com" }
    get admin_index_path
    assert_response :success
    assert_select "script:not([src])", 0
    assert_select "[onclick]", 0
    assert_select "meta[http-equiv]", 0
    assert response.headers["Content-Security-Policy"].present?
  end

  test "production boot: HSTS, CSP and friends are sent; http is redirected to https" do
    out = ProductionBoot.run(<<~'RUBY')
      mock = Rack::MockRequest.new(Rails.application)
      https = mock.get("https://voce.example/about", "HTTPS" => "on")
      proxied = mock.get("http://voce.example/about", "HTTP_X_FORWARDED_PROTO" => "https")
      http = mock.get("http://voce.example/about")
      health = mock.get("http://voce.example/up")
      puts "HTTPS_STATUS=#{https.status}"
      %w[strict-transport-security content-security-policy x-content-type-options x-frame-options referrer-policy permissions-policy set-cookie].each do |h|
        puts "HDR #{h}=#{https.headers[h].inspect}"
      end
      puts "PROXIED_STATUS=#{proxied.status}"
      puts "HTTP_STATUS=#{http.status} LOCATION=#{http.headers['location']}"
      puts "HEALTH_STATUS=#{health.status}"
    RUBY

    assert_match(/HTTPS_STATUS=200/, out)
    assert_match(/HDR strict-transport-security="max-age=31556952; includeSubDomains"/, out)
    assert_match(/HDR content-security-policy=".*script-src 'self'.*upgrade-insecure-requests/, out)
    assert_match(/HDR x-content-type-options="nosniff"/, out)
    assert_match(/HDR x-frame-options="DENY"/, out)
    assert_match(/HDR referrer-policy="no-referrer"/, out)
    assert_match(/HDR permissions-policy=".*geolocation=\(\)/, out)
    assert_match(/HDR set-cookie=nil/, out)
    assert_match(/PROXIED_STATUS=200/, out)
    assert_match(%r{HTTP_STATUS=301 LOCATION=https://voce.example/about}, out)
    assert_match(/HEALTH_STATUS=200/, out)
  end
end
