# Cookie-free CSRF protection for state-changing requests of anonymous visitors.
#
# Rails' regular authenticity token lives in the session, i.e. in a cookie. Where we must not
# hand out a cookie before it is needed (the public pages, GET /admin/login), a request is
# instead verified statelessly:
#   1. Sec-Fetch-Site must be "same-origin" (or, in old browsers without it, Origin/Referer must
#      have this site's host);
#   2. (see same_origin_request? for the details, incl. `Origin: null` under no-referrer)
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

  # Is this state-changing request provably from one of our own pages?
  #
  # * Sec-Fetch-Site (sent by all current browsers, cannot be set by pages) decides when present:
  #   only "same-origin" passes. "none" (user typed the URL / bookmark) makes no sense for a
  #   POST, and "same-site" / "cross-site" are other origins.
  # * Why not just compare Origin? We send `Referrer-Policy: no-referrer`, and browsers then
  #   send `Origin: null` (and no Referer) even on same-origin form / fetch POSTs.
  # * Only when Sec-Fetch-Site is absent (old browsers) fall back to Origin, then Referer,
  #   compared by HOST (not scheme/port: behind the TLS-terminating proxy the scheme the app
  #   sees may differ). "null" or neither header => rejected.
  def same_origin_request?
    fetch_site = request.headers["Sec-Fetch-Site"].to_s.strip.downcase
    return fetch_site == "same-origin" if fetch_site.present?

    source = request.origin.presence || request.referer.presence
    return false if source.nil? || source == "null"

    host = URI.parse(source).host.to_s.downcase
    host.present? && host == request.host.to_s.downcase
  rescue URI::InvalidURIError
    false
  end
end
