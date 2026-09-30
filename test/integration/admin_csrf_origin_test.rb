require "test_helper"

# Regression: logged-in admin POST/PATCH/DELETE returned 422 because Rails' own Origin check
# rejects `Origin: null` (what browsers send under `Referrer-Policy: no-referrer`). The session
# authenticity token is still required; the origin check is now AdminArea#valid_request_origin?
# (same rules as the stateless public/login check).
class AdminCsrfOriginTest < ActionDispatch::IntegrationTest
  setup do
    https!
    RateLimiter::RateLimit.delete_all
    @option = Option.create!(text: "Em revisão", status: "approved", category: "good", needs_review: true, report_count: 2)
    @other = Option.create!(text: "Outra opção", status: "approved", category: "good", needs_review: true)
    get admin_login_path
    token = css_select("input[name=login_token]").first["value"]
    post admin_login_path, params: { secret: AdminSecret.value, login_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_index_path
  end

  def token_for(path, action)
    get path
    css_select("form[action^='#{action}'] input[name=authenticity_token]").first["value"]
  end

  # ---- real browser headers: Origin null + Sec-Fetch-Site same-origin + valid session token ----

  test "Aprovar works with browser headers" do
    token = token_for(admin_review_path, admin_approve_path(@option))
    post admin_approve_path(@option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_review_path
    assert_equal [ false, 0 ], [ @option.reload.needs_review, @option.report_count ]
  end

  test "Excluir from the queue works with browser headers" do
    token = token_for(confirm_delete_admin_option_path(@option, from: "review"), admin_option_path(@option))
    delete admin_option_path(@option, from: "review"), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_review_path
    refute Option.exists?(@option.id)
  end

  test "delete through the confirmation page works with browser headers" do
    get confirm_delete_admin_option_path(@option)
    assert_response :success
    token = css_select("form[action^='/admin/options/#{@option.id}'] input[name=authenticity_token]").first["value"]
    delete admin_option_path(@option), params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_options_path
    refute Option.exists?(@option.id)
  end

  test "edit (text) and category change work with browser headers" do
    token = token_for(edit_admin_option_path(@option), admin_option_path(@option))
    patch admin_option_path(@option), params: { option: { text: "Texto editado", category: "bad" }, authenticity_token: token },
          headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to admin_options_path
    assert_equal [ "Texto editado", "bad" ], [ @option.reload.text, @option.category ]
  end

  test "logout works with browser headers" do
    token = token_for(admin_index_path, admin_logout_path)
    delete admin_logout_path, params: { authenticity_token: token }, headers: BROWSER_ADMIN_HEADERS
    assert_redirected_to root_path
    get admin_index_path
    assert_redirected_to admin_login_path
  end

  test "old browsers without Sec-Fetch-Site: a same-host Origin passes" do
    token = token_for(admin_review_path, admin_approve_path(@option))
    post admin_approve_path(@option), params: { authenticity_token: token }, headers: { "Origin" => "https://www.example.com" }
    assert_redirected_to admin_review_path
  end

  # ---- still protected ----------------------------------------------------------------------

  test "cross-site, same-site, none or bogus Sec-Fetch-Site is refused even with a valid token" do
    token = token_for(admin_review_path, admin_approve_path(@option))
    %w[cross-site same-site none bogus].each do |value|
      post admin_approve_path(@option), params: { authenticity_token: token }, headers: { "Origin" => "null", "Sec-Fetch-Site" => value }
      assert_response :unprocessable_entity, value
    end
    assert @option.reload.needs_review
    assert_equal 2, @option.report_count
  end

  test "Origin null alone (no Sec-Fetch-Site), a foreign Origin, or nothing at all are refused" do
    token = token_for(confirm_delete_admin_option_path(@option, from: "review"), admin_option_path(@option))
    [ { "Origin" => "null" }, { "Origin" => "https://evil.example" }, { "Origin" => "https://www.example.com.evil.example" }, {} ].each do |headers|
      delete admin_option_path(@option, from: "review"), params: { authenticity_token: token }, headers: headers
      assert_response :unprocessable_entity, headers.inspect
    end
    assert Option.exists?(@option.id)
  end

  test "a missing, forged or another form's token is refused even with perfect browser headers" do
    [ nil, "forged", token_for(admin_review_path, admin_approve_path(@other)) ].each do |token|
      post admin_approve_path(@option), params: { authenticity_token: token }.compact, headers: BROWSER_ADMIN_HEADERS
      assert_response :unprocessable_entity, token.inspect
    end
    patch admin_option_path(@option), params: { option: { text: "Hack" } }, headers: BROWSER_ADMIN_HEADERS
    assert_response :unprocessable_entity
    delete admin_option_path(@option), headers: BROWSER_ADMIN_HEADERS
    assert_response :unprocessable_entity
    delete admin_logout_path, headers: BROWSER_ADMIN_HEADERS
    assert_response :unprocessable_entity
    assert Option.exists?(@option.id)
    assert_equal "Em revisão", @option.reload.text
  end

  # ---- public endpoints use their own check and must not 422 for real browser headers ----------------

  test "public POSTs (vote, submit, report) work with Origin null + same-origin + form token" do
    get root_path
    form_token = css_select('meta[name="form-token"]').first["content"]
    headers = BROWSER_ADMIN_HEADERS.merge("CONTENT_TYPE" => "application/json", "Accept" => "application/json", "X-Form-Token" => form_token)
    hash = PairGenerator.hash_for(@option, @other)

    post votes_path, params: { option_id: @option.id, pair_hash: hash }.to_json, headers: headers
    assert_response :success
    post options_path, params: { text: "Nova pública", category: "good" }.to_json, headers: headers
    assert_response :success
    post report_option_path(@other), headers: headers
    assert_response :success
  end
end
