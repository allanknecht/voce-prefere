# Cookie-free CSRF protection for state-changing requests of anonymous visitors.
#
# Rails' regular authenticity token lives in the session, i.e. in a cookie. Where we must not
# hand out a cookie before it is needed (the public pages, GET /admin/login), a request is
# instead verified statelessly:
#   1. Sec-Fetch-Site (if sent by the browser) must not be "cross-site";
#   2. Origin (or, as a fallback, Referer) must match this site's own origin;
#   3. a short-lived, signed, purpose-bound token, embedded in the page we served, must be echoed.
# Cross-site pages cannot forge (1) and (2) from a browser and cannot read our HTML to get (3).
module StatelessCsrf
  extend ActiveSupport::Concern

  private

  def stateless_token_verifier(purpose)
    Rails.application.message_verifier(:"#{purpose}_csrf")
  end

  def generate_stateless_token(purpose, ttl)
    stateless_token_verifier(purpose).generate(SecureRandom.hex(8), purpose: purpose, expires_in: ttl)
  end

  def valid_stateless_token?(token, purpose)
    token = token.to_s
    token.present? && stateless_token_verifier(purpose).verified(token, purpose: purpose).present?
  end

  def same_origin_request?
    fetch_site = request.headers["Sec-Fetch-Site"]
    return false if fetch_site.present? && !%w[same-origin none].include?(fetch_site)

    origin = request.origin.presence
    return origin == request.base_url if origin

    referer = request.referer.presence
    return false unless referer

    uri = URI.parse(referer)
    return false unless uri.scheme && uri.host

    referer_origin = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port && uri.port != uri.default_port}"
    referer_origin == request.base_url
  rescue URI::InvalidURIError
    false
  end
end
