# Você Prefere? 🤔

A privacy-first, mobile-first Brazilian Portuguese "Would You Rather" web app built with Ruby on Rails 8.

Users submit short "Eu prefiro..." options and vote on random pairs. There are **no accounts, no
tracking, no third-party analytics** and **no client IPs in the database or in the logs**.

## Features

- Random pairs, a shareable URL per pair (Web Share API), "Par do Dia" and a "most controversial" ranking
- Good/bad categories (pairs never mix them), options go live immediately and are reviewed afterwards in a persistent queue (`/admin/review`: Aprovar / Reprovar), admin tools to edit/search/delete every option
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
RAILS_ENV=test bin/rails db:prepare && bin/rails test   # unit, controller and integration tests
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

### Keep-alive (optional)

`.github/workflows/keepalive.yml` calls `GET /up` every 10 minutes (and on demand via *Run workflow*), so the
Render free web service does not fall asleep after 15 idle minutes. The URL comes from the repository variable
`KEEPALIVE_URL` (Settings → Secrets and variables → Actions → Variables) and defaults to the production URL. The workflow has no secrets and no permissions.

- `/up` deliberately does **not** touch the database: it keeps the *web service* awake, but **Neon may still
  wake up (a few seconds) on the first request that needs the database**. This also keeps Neon's compute-hours low.
- GitHub **disables scheduled workflows after 60 days without repository activity**: push a commit or re-enable
  the workflow in the *Actions* tab if the pings stop. Scheduled runs can also be delayed by several minutes.

## Admin panel

Open `/admin/login` and submit the password in the form (it is never accepted in a URL / query string).
After login you can review the queue of new/reported options (`/admin/review`), manage all options (`/admin/options`: alphabetical, filters, search, edit, category, delete) and browse the deleted texts (`/admin/deleted`). The session lasts 1 hour and lives in a
cookie that is `Secure`, `HttpOnly`, `SameSite=Strict` and limited to `Path=/admin`. The cookie is only issued
**after a successful login**: `GET /admin/login` (visited by anonymous users and scanners) sets no cookie. The login
POST is protected without a session by a same-origin check (`Sec-Fetch-Site`/`Origin`/`Referer`) plus a signed,
purpose-bound, 1-hour token in the form, and by the brute-force throttle. Approve/reject/logout are protected by
Rails' session-based CSRF tokens. Login attempts are rate limited.

## Categories, review queue and moderation

- **Categories:** every option is `good` (something nice to have/do) or `bad` (pain, gross, violent, a "lesser evil"
  dilemma). **Pairs are only built inside one category** (good × good, bad × bad), on the home page, in "Par do Dia" and
  in the controversial ranking (old mixed pairs are no longer ranked). A category is drawn proportionally to its number
  of options; a category with a single option cannot form a pair. The category is guessed by `OptionClassifier`
  (accent/case-insensitive whole-word signals: body/sex/gross, pain/violence, scary animals, "por 10 anos"/"3x ao dia"
  penalties, ...; anything else is good) and can be changed in `/admin/options` (edit page, plus a category filter).
- **No automatic moderation of new submissions.** A submitted option is **live immediately** and enters the
  **persistent review queue** (`options.needs_review`) shown at `/admin/review` (linked, with the count, on the admin
  dashboard: the link is highlighted when the queue is not empty). **Aprovar** takes it out of the queue (and resets its
  report count); **Reprovar** deletes the option **for good**, together with its votes and the votes of pairs that
  contain it, in one transaction, and keeps its text (and category) in `deleted_options` (reason `reprovada`;
  `manual` for deletions in `/admin/options`), browsable read-only at `/admin/deleted`. No IP or author data is stored.
- **Reports:** at **3 reports** an option goes **off air** (`status = pending`) and back into the review queue;
  Aprovar puts it on air again with the count reset.
- `ContentModerator` (blocklists from `MODERATION_BLOCKLIST` / `MODERATION_NAMES_BLOCKLIST`) is no longer applied to
  public submissions; it is only used as a **warning when the admin edits a text** (saving a flagged text needs the
  explicit "forçar" checkbox).
- **Migration** (`AddReviewQueueAndCategoriesToOptions`, runs at deploy through `bin/docker-entrypoint` → `db:prepare`;
  works on SQLite and PostgreSQL, reversible, deletes nothing): adds `needs_review`, classifies every existing option,
  keeps approved ones as they are, makes old `pending` options visible and puts them in the queue (except those that were
  pending because of 3+ reports: they stay off air, in the queue), and leaves `rejected` ones hidden and out of the queue.

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
app/services/      OptionClassifier, ContentModerator, RateLimiter, PairGenerator
app/assets/javascripts/application.js   the only script (no inline JS)
lib/privacy/       IP scrubbing for logs (Rails logger, BroadcastLogger, Puma)
config/initializers/  CSP, security headers, session cookie, admin secret check, log privacy
```

## License

MIT
