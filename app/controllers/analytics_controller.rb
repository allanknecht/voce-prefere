# First-party analytics beacon, called by our own script after a public page loaded
# ({kind: "visit", ...}) and when Compartilhar is clicked ({kind: "share_click"}).
#
# * Same-origin only (Sec-Fetch-Site, see StatelessCsrf) and rate limited per hashed IP. No form
#   token: the publicly cached pages (about, polêmicos) have none, and the endpoint only appends a
#   counter row, never reads or changes anything else.
# * Whitelisted kinds, whitelisted screens, sanitized values (see Analytics). Always answers
#   204 No Content (also for bots / GPC / DNT: they are simply not recorded).
# * No cookie, nothing about the request is stored besides the aggregated, anonymous fields.
class AnalyticsController < ApplicationController
  include PublicRequest

  KINDS = %w[visit share_click].freeze

  def create
    kind = params[:kind].to_s
    return head :unprocessable_entity unless KINDS.include?(kind)
    return head :too_many_requests unless RateLimiter.check(request.remote_ip, :beacon)

    if kind == "visit"
      source = Analytics.source_tag(params[:tag]) || Analytics.referrer_source(params[:referrer], own_host: request.host)
      Analytics.record_visit(request, screen: params[:screen].to_s, pair_hash: params[:pair_hash], source: source,
                                      via_share: flag(params[:via_share]), returning: flag(params[:returning]))
    else
      Analytics.record_event(request, "share_click", pair_hash: params[:pair_hash])
    end
    Analytics.later(request) { RateLimiter.record(request.remote_ip, :beacon) }
    head :no_content
  end

  private

  # only a real JSON true (or the string "true") counts
  def flag(value)
    value == true || value.to_s == "true"
  end

  # Same-origin check only (see above); the shared token is not required for the beacon.
  def verify_public_request
    return if same_origin_request?

    head :forbidden
  end
end
