# Você Prefere? 🤔

A privacy-first, mobile-first Brazilian Portuguese "Would You Rather" web app built with Ruby on Rails 8.

Users submit short "Eu prefiro..." options and vote on random pairs. There are **no accounts, no
tracking, no third-party analytics** and **no client IPs in the database or in the logs**.

## Features

- Random pairs, a shareable URL per pair (Web Share API), "Par do Dia" and a "most controversial" ranking
- Automatic moderation (blocklists from environment variables + a narrow full-name heuristic), manual review in `/admin`
- Anti-spam rate limiting with **hashed** IPs (`rate_limits` table, no Redis)
- Real HTTP security headers: CSP without `unsafe-inline`, HSTS, nosniff, Referrer-Policy, Permissions-Policy, X-Frame-Options
- Stateless CSRF protection on public forms (Origin/Referer + signed token) so public pages stay **cookie-free**

## Tech stack

Rails 8.1 · Ruby 3.3.6 · PostgreSQL in production (`DATABASE_URL`, e.g. Neon) · SQLite for local dev/tests ·
Propshaft + Tailwind CSS · one small plain JavaScript file (no Turbo/Stimulus/importmap) · Minitest.
No Redis, no persistent disk, no background workers, no Action Cable / Active Storage / Action Mailer.

## Local setup

```bash
# Ruby 3.3.6 (see .ruby-version)
bundle install
bin/rails db:prepare       # creates storage/development.sqlite3 and loads the 22 seed options
bin/dev                    # http://localhost:3000
```

Development/test need no environment variables (the admin password in development/test is `dev-admin-secret`).

### Tests and checks

```bash
RAILS_ENV=test bin/rails db:prepare test   # unit, controller and integration tests
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

The integration tests boot the real **production** environment in a subprocess to verify HSTS/CSP headers,
the fail-fast `ADMIN_SECRET` check and that no IP address reaches the log.

## Environment variables (production)

| Variable | Required | Purpose |
| --- | --- | --- |
| `SECRET_KEY_BASE` | **yes** | Rails secret (cookies, signed form tokens, salt for the IP hashes). `bin/rails secret` |
| `ADMIN_SECRET` | **yes** | Password for `/admin/login`. The app **refuses to boot** if it is unset, shorter than 16 characters or equals the old placeholder. `openssl rand -hex 32` |
| `DATABASE_URL` | **yes** | PostgreSQL URL, e.g. Neon: `postgresql://user:pass@host/db?sslmode=require` |
| `MODERATION_BLOCKLIST` | recommended | Comma/newline separated profanity/explicit terms (not stored in the repo) |
| `MODERATION_NAMES_BLOCKLIST` | recommended | Comma/newline separated names of real people, politicians, brands (not stored in the repo) |
| `RAILS_LOG_LEVEL` | no | Defaults to `info` |

There is **no** `credentials.yml.enc` and **no** `RAILS_MASTER_KEY`: everything comes from the environment.
See `.env.example`.

## Deployment

Render (free web service) + Neon (free Postgres) via the included `Dockerfile` and `render.yaml`.
Render's free tier has **no persistent disk** and the service **sleeps after 15 minutes without traffic**
(the next request takes ~30–60 s). Full guide: [DEPLOYMENT.md](DEPLOYMENT.md).

## Admin panel

Open `/admin/login` and submit the password in the form (it is never accepted in a URL / query string).
After login you can approve/reject pending and reported options. The session lasts 1 hour and lives in a
cookie that is `Secure`, `HttpOnly`, `SameSite=Strict` and limited to `Path=/admin`. Approve/reject/logout are
protected by Rails' session-based CSRF tokens. Login attempts are rate limited.

## Content moderation

New submissions are normalized (accents, spacing and leetspeak removed) and checked against the blocklists
above. Real people are caught primarily by `MODERATION_NAMES_BLOCKLIST` (short names match whole words only,
so "ana" does not flag "banana"). A deliberately narrow heuristic also flags two or more consecutive
capitalized words in the middle of a sentence ("Votar em João Silva"); single capitalized words such as
"Brasil" or "Netflix", sentence-initial capitals and well-known places ("São Paulo") are allowed.
Flagged submissions become `pending` for manual review. Three user reports send an option back to `pending`.
The repo only ships harmless placeholder lists as defaults.

## Rate limiting

`SHA256(secret + hour window + IP + action)` is stored in `rate_limits` with an expiry ≤ 1 hour; raw IPs are
never stored. Limits per hour: submit 5, vote 100, report 10; admin login 5 per 15 minutes.

## Privacy summary

See [PRIVACY.md](PRIVACY.md) for details and code references. In short: no accounts, no cookies on public pages,
no third-party requests (CSP enforces it), no IPs stored or logged, no analytics.

## Project structure

```
app/controllers/   Pages, Pairs, Votes, Options (public), Admin, AdminSessions
app/controllers/concerns/  PublicRequest (cookie-free CSRF), AdminArea
app/services/      ContentModerator, RateLimiter, PairGenerator
app/assets/javascripts/application.js   the only script (no inline JS)
lib/privacy/       IP scrubbing for logs (Rails logger, BroadcastLogger, Puma)
config/initializers/  CSP, security headers, session cookie, admin secret check, log privacy
```

## License

MIT
