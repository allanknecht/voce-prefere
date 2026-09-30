require "test_helper"

# Public POST endpoints (vote / submit / report) are cookie-free, so CSRF protection is
# stateless: Origin/Referer/Sec-Fetch-Site check + signed form token (see PublicRequest).
class PublicCsrfTest < ActionDispatch::IntegrationTest
  setup do
    RateLimiter::RateLimit.delete_all
    @a = Option.create!(text: "Opção A", status: "approved")
    @b = Option.create!(text: "Opção B", status: "approved")
    @pair = [ @a.id, @b.id ].sort.join("-")
  end

  def vote(headers, option: @a)
    post votes_path, params: { option_id: option.id, pair_hash: @pair }.to_json, headers: headers
  end

  test "home page embeds a token and sets no cookie" do
    get root_path
    assert_select 'meta[name="form-token"][content]'
    assert_nil response.headers["Set-Cookie"]
  end

  test "vote works with token + same origin, and sets no cookie" do
    assert_difference -> { Vote.count }, 1 do
      vote(public_post_headers)
    end
    assert_response :success
    assert_equal true, response.parsed_body["success"]
    assert_nil response.headers["Set-Cookie"]
  end

  test "vote is rejected without token" do
    assert_no_difference -> { Vote.count } do
      vote(public_post_headers.except("X-Form-Token"))
    end
    assert_response :forbidden
    assert_nil response.headers["Set-Cookie"]
  end

  test "vote is rejected with a forged or foreign token" do
    assert_no_difference -> { Vote.count } do
      vote(public_post_headers(token: "forged"))
      assert_response :forbidden
      vote(public_post_headers(token: Rails.application.message_verifier(:other).generate("x", purpose: :public_form)))
      assert_response :forbidden
    end
  end

  test "vote is rejected with an expired token" do
    token = form_token
    travel 25.hours do
      assert_no_difference -> { Vote.count } do
        vote(public_post_headers(token: token))
      end
      assert_response :forbidden
    end
  end

  test "vote is rejected from a cross-site Origin even with a valid token" do
    token = form_token
    assert_no_difference -> { Vote.count } do
      vote(public_post_headers(token: token, origin: "https://evil.example"))
    end
    assert_response :forbidden
  end

  test "vote is rejected when Sec-Fetch-Site says cross-site" do
    token = form_token
    assert_no_difference -> { Vote.count } do
      vote(public_post_headers(token: token, extra: { "Sec-Fetch-Site" => "cross-site" }))
    end
    assert_response :forbidden
  end

  test "Referer is accepted when Origin is missing, and must match" do
    token = form_token
    headers = public_post_headers(token: token).except("Origin")

    assert_difference -> { Vote.count }, 1 do
      vote(headers.merge("Referer" => "http://www.example.com/pairs/#{@pair}"))
    end
    assert_no_difference -> { Vote.count } do
      vote(headers.merge("Referer" => "https://evil.example/www.example.com"))
      assert_response :forbidden
      vote(headers)
      assert_response :forbidden
    end
  end

  test "submit option requires token and origin" do
    post options_path, params: { text: "Sem token" }.to_json, headers: { "CONTENT_TYPE" => "application/json", "Origin" => "http://www.example.com" }
    assert_response :forbidden
    assert_nil Option.find_by(text: "Sem token")

    post options_path, params: { text: "Com token" }.to_json, headers: public_post_headers
    assert_response :success
    assert Option.find_by(text: "Com token")
    assert_nil response.headers["Set-Cookie"]
  end

  test "report requires token and origin" do
    post report_option_path(@a), headers: { "Origin" => "http://www.example.com" }
    assert_response :forbidden
    assert_equal 0, @a.reload.report_count

    post report_option_path(@a), headers: public_post_headers
    assert_response :success
    assert_equal 1, @a.reload.report_count
  end

  test "vote validates its parameters" do
    post votes_path, params: { option_id: @a.id, pair_hash: "1-2; drop table" }.to_json, headers: public_post_headers
    assert_response :unprocessable_entity
    post votes_path, params: { option_id: @a.id, pair_hash: "998-999" }.to_json, headers: public_post_headers
    assert_response :unprocessable_entity
  end

  test "GET pages are not blocked by the check" do
    get pairs_day_path
    assert_includes [ 200, 302 ], response.status
  end
end
