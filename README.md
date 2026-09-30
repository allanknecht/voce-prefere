# Você Prefere? 🤔

A privacy-first, mobile-first Brazilian Portuguese "Would You Rather" web app built with Ruby on Rails 8.

Users submit short "Eu prefiro..." options and vote on random pairs. There are **no accounts, no
tracking, no third-party analytics** and **no client IPs in the database or in the logs**.

## Features

- Random pairs, a shareable URL per pair (Web Share API), "Par do Dia" and a "most controversial" ranking
- Good/bad categories (pairs never mix them), options go live immediately and are reviewed afterwards in a persistent queue (`/admin/review`: Aprovar / Excluir); **no automatic filter or removal of any kind**, admin tools to edit/search/delete every option
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
purpose-bound, 1-hour token in the form, and by the brute-force throttle. Approve/delete/edit/logout are protected by
Rails' session-based CSRF tokens. Login attempts are rate limited.

## Categories and review queue

- **Categories:** every option is `good` (something nice to have/do) or `bad` (pain, gross, violent, a "lesser evil"
  dilemma). **Pairs are only built inside one category** (good × good, bad × bad), on the home page, in "Par do Dia" and
  in the controversial ranking (old mixed pairs are no longer ranked). A category is drawn proportionally to its number
  of options; a category with a single option cannot form a pair. In the **submission form the user chooses Boa or Ruim**
  (required radio buttons, nothing preselected; the server answers 422 "Escolha se a opção é Boa ou Ruim" when it is missing
  or invalid). `OptionClassifier` is only a fallback for non-form paths and the data migration, where the category is guessed
  (accent/case-insensitive whole-word signals: body/sex/gross, pain/violence, scary animals, "por 10 anos"/"3x ao dia"
  penalties, ...; anything else is good) and can be changed in `/admin/options` (edit page, plus a category filter).
- **No automatic filter, nothing is removed or hidden automatically.** There is no word/name blocklist
  (`ContentModerator` and the `MODERATION_*` variables are gone; if they are still set on Render they are ignored), no
  automatic rejection and no automatic take-down. A submitted option is **live immediately** and enters the
  **persistent review queue** (`options.needs_review`) at `/admin/review` (linked, with the count, on the admin
  dashboard; the link is highlighted when the queue is not empty).
- **Queue actions:** **Aprovar** = stays/goes **on the air**, leaves the queue and resets the report count to 0 (so a
  later report queues it again). **Excluir** (with a confirmation page stating how many votes go away) deletes the
  option **for good** together with its votes and the votes of pairs that contain it, in one transaction, and keeps
  its text and category in `deleted_options` (`reason` stored as `reprovada`/`manual`, shown in `/admin/deleted` as
  "Excluída na fila" / "Excluída manualmente"; read-only, no author/IP data).
- **Reports do not take anything off the air.** The report button (hashed-IP rate limiting) only increments
  `report_count` and puts the option in the queue (`needs_review = true`). The queue lists **reported options first**
  (most reports first, red border and a "🚩 N denúncias" badge), then the oldest ones.
- **Off-air options:** the old moderation left some options `rejected`/`pending` (hidden). The migration
  `QueueAllOffAirOptions` (idempotent, deletes nothing, does **not** put anything on the air) flags all of them
  `needs_review`, so they appear in the queue with a "Fora do ar" badge: Aprovar puts them on the air, Excluir deletes
  them. Public pages only ever show `approved` options.
- **Admin edit** (`/admin/options`) only validates the length (1–120) and duplicates (case/accent-insensitive); there is
  no content warning and no "forçar".
- **Migrations** (run at deploy through `bin/docker-entrypoint` → `db:prepare`; SQLite and PostgreSQL; nothing is
  deleted): `AddReviewQueueAndCategoriesToOptions` (adds `needs_review`, classifies existing options) and
  `QueueAllOffAirOptions` (above).

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
app/services/      OptionClassifier, RateLimiter, PairGenerator
app/assets/javascripts/application.js   the only script (no inline JS)
lib/privacy/       IP scrubbing for logs (Rails logger, BroadcastLogger, Puma)
config/initializers/  CSP, security headers, session cookie, admin secret check, log privacy
```

## License

MIT
