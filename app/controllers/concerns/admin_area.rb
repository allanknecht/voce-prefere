# Shared behaviour for the admin area. Unlike the public pages, admin uses a
# (short-lived, Path=/admin, Secure, HttpOnly, SameSite=Strict) session cookie and
# Rails' regular session-based CSRF protection (the authenticity token must be valid).
#
# Rails' own Origin check is replaced by ours (StatelessCsrf#same_origin_request?): with
# `Referrer-Policy: no-referrer` browsers send `Origin: null` on same-origin form posts, which
# Rails rejects outright. So: Sec-Fetch-Site must be "same-origin"; only when the browser does
# not send it, Origin/Referer are compared by host; `null` / nothing at all is refused.
module AdminArea
  extend ActiveSupport::Concern
  include StatelessCsrf

  included do
    protect_from_forgery with: :exception
    before_action :no_store
  end

  private

  def no_store
    response.headers["Cache-Control"] = "no-store"
  end

  # Called by Rails' verify_authenticity_token together with the token check.
  def valid_request_origin?
    same_origin_request?
  end
end
