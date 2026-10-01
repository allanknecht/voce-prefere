# Privacy implementation

What the app does and does not do, with the code that enforces it. Verified by tests in `test/`.

## No accounts, login or email

- No user model, no email collection. Only the moderator uses a shared password (`ADMIN_SECRET`).

## Cookies

- **Public pages set no cookies at all** (no `Set-Cookie`): the session is disabled for them
  (`app/controllers/concerns/public_request.rb`), tested in `test/controllers/privacy_test.rb` and `test/integration/`.
- The **only cookie** is the admin session cookie `_voce_prefere_admin`, set only on `/admin/*`:
  `Path=/admin`, `Secure`, `HttpOnly`, `SameSite=Strict`, expires after 1 hour
  (`config/initializers/session_store.rb`, tested in `test/integration/admin_test.rb`).
- Vote de-duplication and "Próximo" use the browser's `localStorage` only (`voted_<pair>` and a list `seen_pairs` of the polls
  already voted on, capped at 500; never sent to the server). The server only embeds a few candidate pair links in the page;
  the script picks the first one this browser has not voted on. Without storage (private mode) the first candidate is used.

## CSRF

- **Admin** (login, approve, delete, logout): Rails' session-based authenticity token (`protect_from_forgery`,
  `app/controllers/concerns/admin_area.rb`), login form is a POST form (`/admin/login`), no `?secret=` URLs.
- **Public POSTs** (vote, submit option, report): there is no session, so CSRF protection is **stateless**:
  each request must (1) not be `Sec-Fetch-Site: cross-site`, (2) carry an `Origin` (or `Referer`) equal to the site's
  own origin, and (3) carry a signed, expiring (24 h) token in the `X-Form-Token` header, taken from a
  `<meta name="form-token">` tag in the page. This keeps public pages cookie-free.
  **Trade-off:** the token is not bound to a browser (no cookie to bind it to), so it proves "the request came from
  a page served by us / a script that fetched our HTML", not "from this particular user". A script that fetches the
  HTML directly (curl) can still obtain a token, so this stops cross-site request forgery, not scripted abuse; the
  hashed-IP rate limiter is the defence against that.

## IP addresses

- **Database:** raw IPs are never stored. The rate limiter stores `SHA256(secret + hour window + IP + action)` in
  `rate_limits`, with an expiry of at most 1 hour (`app/services/rate_limiter.rb`). Without the secret the hash
  cannot be reversed, and the salt changes every hour. The same table holds a 10-second "double vote" guard
  (`SHA256(secret + window + IP + vote pair)`, expiring after 10 s): a repeated click on the same pair is not counted twice.
  No cookie, no new personal data.
- **Logs:** raw IPs never reach the Rails log. Rails' `Started GET "/" for <ip>` line is replaced by
  `Started GET "/" at <time>` (`lib/privacy/rack_logger.rb`, swapped in for `Rails::Rack::Logger`), and every logger,
  including each logger inside `ActiveSupport::BroadcastLogger`, additionally replaces any IPv4/IPv6 literal that
  might still appear in a message with `[ip-redacted]` (`lib/privacy/ip_scrubber.rb`). Puma's own error output is
  patched the same way (`lib/privacy/puma_error_logger.rb`). Tests: `test/lib/ip_scrubber_test.rb` and
  `test/integration/ip_logging_test.rb` (boots production mode and greps the log for fake IPs `203.0.113.7` and
  `2001:db8::7`).
- **Remaining caveat:** the hosting platform itself (Render's load balancer/edge, Neon) sees IPs in its own
  infrastructure; that is outside this app's control. The app only sees the address in memory, to compute the hash.

## First-party analytics (anonymous, server side)

Code: `app/services/analytics.rb`, `app/services/analytics/*`, `AnalyticsController` (`POST /m`), `/admin/stats`.

**Measured** (tables `visits`, `events`, `daily_stats`): day and hour (America/Sao_Paulo), screen kind (home / pair / results / day /
controversial / about / other, never a URL), the pair hash on pair screens, device class (mobile / desktop / tablet),
referrer **registrable domain only** (e.g. `google.com`, `direto`; never path or query) or a sanitized `?s=` / `?utm_source=` tag
(`[a-z0-9_-]{1,24}`), `via_share` (arrived through a link made by Compartilhar, which carries `?c=1`), `returning` (a boolean, see below),
and for events: `vote`, `submit_option`, `share_click`, `shared_link_visit`, `report` (option id only for vote/report, never any text).

**Not measured / not stored**: no cookie, no raw IP, no user agent, no full URL, no option text, no fingerprint, no third party, no external script.
There is nothing that identifies a person and nothing that links the same person across days.

- `visitor_hash` = first 16 hex of `HMAC-SHA256(daily_salt, "ip|user_agent")` with `daily_salt = HMAC(key derived from SECRET_KEY_BASE, ISO date)`.
  The salt changes every day, so the hash is not reversible to an IP/UA and cannot be linked from one day to the next.
  Consequently **visitors are counted per day** (the same person on two days counts twice). The IP and the UA only exist in memory
  while computing the hash; they are never written to the database or the log.
- **Returning visitors without an identifier**: the script keeps the date of the last visit in `localStorage` (`last_visit`) and sends only
  the boolean `returning` (= that date is before today). The date never leaves the browser. Without storage the visit counts as new.
- **How a visit is recorded**: public pages are `no-cache`; right after load, our own script sends ONE `POST /m {kind: "visit", ...}`
  (`fetch` with `keepalive`, `credentials: "omit"`) and the server records the visit then (the page `GET` records nothing, so there is no double count).
  `share_click` is a second beacon. `vote` / `submit_option` / `report` are recorded by their controllers after success.
  The insert runs after the response was sent (`rack.after_reply`) and every error is rescued: analytics can never break a request.
- **Beacon protection**: same-origin only (`Sec-Fetch-Site`, see CSRF above), whitelisted kinds (`visit`, `share_click`) and screens, rate limited by
  the existing hashed-IP limiter, always `204`, no cookie.
- **Never recorded**: bots / crawlers / link-preview fetchers / uptime monitors / scripts and empty user agents (list in `Analytics::BOT_PATTERN`,
  tested), `/up`, the admin area, assets, and every request with **`Sec-GPC: 1`** or **`DNT: 1`** (honoured).
- **Retention**: raw rows are kept 90 days, then folded into one `daily_stats` row per day (counts, device counts, top sources, hour histogram,
  funnel counts) and deleted. The compaction runs opportunistically (at most hourly, guarded by an atomic marker row) and with `bin/rails stats:compact`.
- `/admin/stats` is admin-only (`AdminArea`, session + CSRF, `no-store`), server rendered, CSS bars, no JS charts.

## Third parties

- No analytics, no CDN, no fonts, no captcha. Cloudflare Turnstile is **not** integrated, so
  `challenges.cloudflare.com` is not in the CSP. The CSP (`default-src 'none'; script-src 'self'; style-src 'self';
  connect-src 'self'; ...`) blocks any third-party request.

## Security headers (real HTTP headers)

`Content-Security-Policy` (no `unsafe-inline`; all JavaScript is the external `application.js`, no inline styles),
`Strict-Transport-Security` (`force_ssl`, 1 year, includeSubDomains), `X-Content-Type-Options: nosniff`,
`Referrer-Policy: no-referrer`, `Permissions-Policy` (camera, microphone, geolocation, ... disabled),
`X-Frame-Options: DENY`, plus COOP/CORP. Configured in `config/initializers/content_security_policy.rb`,
`config/initializers/security_headers.rb` and `config/environments/production.rb`; tested in
`test/integration/security_headers_test.rb` (including a production-mode boot).

## Admin password

`ADMIN_SECRET` has no default in production: the app refuses to boot when it is unset, shorter than 16 characters or
the old placeholder (`config/initializers/admin_secret.rb`). Comparison is constant-time; login attempts are rate
limited; the session is renewed on login (no fixation) and expires after 1 hour.

## What is stored

Anonymous analytics rows (see above), option texts (with a good/bad category and a review flag), votes per option/pair, report counts, timestamps, the text/category/reason/date of options the admin deleted or rejected (`deleted_options`, no author data), and the short-lived hashed
rate-limit keys. Nothing that identifies a person.

## Input handling

ActiveRecord parameterized queries, ERB auto-escaping, 120-character limit, vote parameters validated; new options go live at once and are reviewed by the admin
afterwards (`/admin/review`), no automatic filtering or removal.
