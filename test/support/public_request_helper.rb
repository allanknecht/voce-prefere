# Helpers for exercising the cookie-free public POST endpoints the way the site's JS does.
module PublicRequestHelper
  def form_token
    get root_path
    css_select('meta[name="form-token"]').first&.[]("content") or flunk("no form-token meta tag on /")
  end

  def public_post_headers(token: form_token, origin: "http://www.example.com", extra: {})
    { "CONTENT_TYPE" => "application/json", "Accept" => "application/json",
      "Origin" => origin, "X-Form-Token" => token }.merge(extra)
  end
end
