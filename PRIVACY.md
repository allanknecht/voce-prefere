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
- Vote de-duplication uses the browser's `localStorage` only (never sent to the server).

## CSRF

- **Admin** (login, approve, reject, logout): Rails' session-based authenticity token (`protect_from_forgery`,
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
  cannot be reversed, and the salt changes every hour.
- **Logs:** raw IPs never reach the Rails log. Rails' `Started GET "/" for <ip>` line is replaced by
  `Started GET "/" at <time>` (`lib/privacy/rack_logger.rb`, swapped in for `Rails::Rack::Logger`), and every logger,
  including each logger inside `ActiveSupport::BroadcastLogger`, additionally replaces any IPv4/IPv6 literal that
  might still appear in a message with `[ip-redacted]` (`lib/privacy/ip_scrubber.rb`). Puma's own error output is
  patched the same way (`lib/privacy/puma_error_logger.rb`). Tests: `test/lib/ip_scrubber_test.rb` and
  `test/integration/ip_logging_test.rb` (boots production mode and greps the log for fake IPs `203.0.113.7` and
  `2001:db8::7`).
- **Remaining caveat:** the hosting platform itself (Render's load balancer/edge, Neon) sees IPs in its own
  infrastructure; that is outside this app's control. The app only sees the address in memory, to compute the hash.

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

Option texts (with a good/bad category and a review flag), votes per option/pair, report counts, timestamps, the text/category/reason/date of options the admin deleted or rejected (`deleted_options`, no author data), and the short-lived hashed
rate-limit keys. Nothing that identifies a person.

## Input handling

ActiveRecord parameterized queries, ERB auto-escaping, 120-character limit, vote parameters validated; new options go live at once and are reviewed by the admin
afterwards (`/admin/review`), no automatic filtering or removal.
