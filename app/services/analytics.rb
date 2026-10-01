# First-party, privacy-first analytics (see PRIVACY.md).
#
# * No cookie, no IP / user agent stored or logged, no third party, no external script.
# * `visitor_hash` = HMAC-SHA256(daily_salt, "ip|user_agent")[0, 16]; the salt is
#   HMAC(app-secret-derived key, ISO date), so the hash changes every day: it is neither
#   reversible nor linkable across days. "Visitors" are therefore counted per day.
# * Not recorded at all: bots / crawlers / monitors / empty user agents, Sec-GPC: 1, DNT: 1,
#   /up, the admin area and assets (only public screens send the beacon).
# * Recording can never break or slow a request: the insert runs after the response was sent
#   (Rack `rack.after_reply`, Puma) and every error is rescued.
module Analytics
  TIME_ZONE = "America/Sao_Paulo".freeze
  RETENTION_DAYS = 90

  BOT_PATTERN = Regexp.union(
    /bot\b/i, /crawl/i, /spider/i, /slurp/i, /facebookexternalhit/i, /facebot/i, /whatsapp/i, /telegram/i, /slack/i,
    /discord/i, /twitter/i, /linkedin/i, /pinterest/i, /preview/i, /embedly/i, /bingpreview/i, /googleother/i,
    /google-read-aloud/i, /duplexweb/i, /lighthouse/i, /pagespeed/i, /gtmetrix/i, /pingdom/i, /uptime/i, /statuscake/i,
    /monitor/i, /datadog/i, /newrelic/i, /headlesschrome/i, /phantomjs/i, /puppeteer/i, /playwright/i, /selenium/i,
    /\bcurl\b/i, /wget/i, /python/i, /\bgo-http-client/i, /java\//i, /okhttp/i, /libwww/i, /httpclient/i,
    /axios/i, /node-fetch/i, /undici/i, /postman/i, /insomnia/i, /github/i, /render\//i, /kube-probe/i, /ahrefs/i, /semrush/i
  ).freeze

  Context = Struct.new(:visitor_hash, :device, :time, keyword_init: true)

  module_function

  def bot?(user_agent)
    ua = user_agent.to_s.strip
    ua.empty? || ua.length < 8 || ua.match?(BOT_PATTERN)
  end

  # Sec-GPC: 1 / DNT: 1 are honoured: nothing is recorded.
  def opted_out?(request)
    request.headers["Sec-GPC"].to_s.strip == "1" || request.headers["DNT"].to_s.strip == "1"
  end

  def local_time(time = Time.current)
    time.in_time_zone(TIME_ZONE)
  end

  def today
    local_time.to_date
  end

  # nil = do not record this request.
  def context(request)
    return nil if opted_out?(request) || bot?(request.user_agent)

    now = local_time
    Context.new(visitor_hash: visitor_hash(request.remote_ip, request.user_agent, now.to_date),
                device: device(request.user_agent), time: now)
  end

  def daily_salt(date)
    OpenSSL::HMAC.digest("SHA256", base_key, date.iso8601)
  end

  def visitor_hash(ip, user_agent, date)
    OpenSSL::HMAC.hexdigest("SHA256", daily_salt(date), "#{ip}|#{user_agent}")[0, 16]
  end

  def base_key
    @base_key ||= Rails.application.key_generator.generate_key("analytics daily salt", 32)
  end

  # mobile / tablet / desktop from the user agent (the user agent itself is never stored)
  def device(user_agent)
    ua = user_agent.to_s
    return "tablet" if ua.match?(/iPad|Tablet|PlayBook|Silk/i) || (ua.match?(/Android/i) && !ua.match?(/Mobile/i))
    return "mobile" if ua.match?(/Mobi|iPhone|iPod|Android|Windows Phone|BlackBerry|Opera Mini/i)

    "desktop"
  end

  # The registrable domain of an incoming referrer, or "direto" / "outro". NEVER path or query.
  # `own_host` (this site) and unparsable values count as "direto".
  def referrer_source(value, own_host: nil)
    raw = value.to_s.strip
    return "direto" if raw.empty? || raw.length > 300

    host =
      if raw.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        return "outro" unless raw.match?(%r{\Ahttps?://}i)

        URI.parse(raw).host.to_s
      elsif raw.match?(/\A[a-z0-9.-]+\z/i)
        raw # already a bare host name (what our script sends)
      else
        return "direto" # javascript:, data:, garbage
      end

    host = host.downcase.delete_suffix(".")
    return "direto" if host.empty? || host.length > 100 || !host.match?(/\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/)
    return "direto" if own_host.present? && (host == own_host.to_s.downcase || host.end_with?(".#{own_host.to_s.downcase}"))
    return "outro" if host.match?(/\A\d+(\.\d+){3}\z/) # an IP address as referrer: not a source name

    registrable_domain(host)
  rescue URI::InvalidURIError
    "direto"
  end

  SECOND_LEVEL = %w[com co org net gov edu ac].freeze

  # No public-suffix list: last two labels, three for com.br / co.uk style suffixes.
  def registrable_domain(host)
    labels = host.split(".")
    keep = labels.length >= 3 && labels[-1].length == 2 && SECOND_LEVEL.include?(labels[-2]) ? 3 : 2
    labels.last(keep).join(".")
  end

  # `?s=tag` / `?utm_source=tag`: only a short [a-z0-9_-] token survives.
  def source_tag(value)
    tag = value.to_s.strip.downcase
    tag.match?(/\A[a-z0-9_-]{1,24}\z/) ? tag : nil
  end

  def safe_pair_hash(value)
    value.to_s.match?(/\A\d{1,18}-\d{1,18}\z/) ? value.to_s : nil
  end

  # Runs the insert after the response was sent when the server supports it (Puma), inline
  # otherwise (tests, other servers). Errors are rescued and logged WITHOUT any request data.
  def later(request, &block)
    job = lambda do
      Rails.application.executor.wrap { block.call }
    rescue StandardError => e
      Rails.logger.warn("analytics write failed: #{e.class}")
    end
    after_reply = request.env["rack.after_reply"]
    after_reply.is_a?(Array) ? after_reply << job : job.call
  end

  def record_event(request, kind, pair_hash: nil, option_id: nil)
    ctx = context(request)
    return unless ctx

    pair = safe_pair_hash(pair_hash)
    later(request) do
      AnalyticsEvent.create!(occurred_at: ctx.time, day: ctx.time.to_date, hour: ctx.time.hour, kind: kind,
                             pair_hash: pair, option_id: option_id, device: ctx.device, visitor_hash: ctx.visitor_hash)
    end
  rescue StandardError => e
    Rails.logger.warn("analytics failed: #{e.class}")
  end

  def record_visit(request, screen:, pair_hash:, source:, via_share:, returning:)
    ctx = context(request)
    return unless ctx

    screen = "other" unless Visit::SCREENS.include?(screen)
    pair = Visit::PAIR_SCREENS.include?(screen) ? safe_pair_hash(pair_hash) : nil
    later(request) do
      Visit.create!(occurred_at: ctx.time, day: ctx.time.to_date, hour: ctx.time.hour, screen: screen, pair_hash: pair,
                    device: ctx.device, source: source, via_share: via_share, returning_visit: returning, visitor_hash: ctx.visitor_hash)
      if via_share
        AnalyticsEvent.create!(occurred_at: ctx.time, day: ctx.time.to_date, hour: ctx.time.hour, kind: "shared_link_visit",
                               pair_hash: pair, device: ctx.device, visitor_hash: ctx.visitor_hash)
      end
      Compactor.run_if_due
    end
  rescue StandardError => e
    Rails.logger.warn("analytics failed: #{e.class}")
  end
end
