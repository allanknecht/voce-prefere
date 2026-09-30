# syntax=docker/dockerfile:1
# check=error=true

# Production image for Render (free web service) or any Docker host.
#   docker build -t voce_prefere .
#   docker run -d -p 3000:3000 -e PORT=3000 \
#     -e SECRET_KEY_BASE=<64+ random hex chars> \
#     -e ADMIN_SECRET=<32+ random chars> \
#     -e DATABASE_URL=postgresql://user:pass@host/db?sslmode=require \
#     --name voce_prefere voce_prefere
#
# The app has no credentials.yml.enc and needs no RAILS_MASTER_KEY: secrets come
# from environment variables (SECRET_KEY_BASE, ADMIN_SECRET, DATABASE_URL).

# Keep RUBY_VERSION in sync with .ruby-version
ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Base runtime packages (libpq5 = PostgreSQL client library for the pg gem)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libpq5 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Production environment; jemalloc keeps memory low on the 512 MB free tier.
# development + test gems (sqlite3, brakeman, rubocop, ...) are not installed.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompile assets (Tailwind CSS + JS). SECRET_KEY_BASE_DUMMY=1 lets Rails boot without
# any real secret (or ADMIN_SECRET / database) at build time; it is only used here.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Final stage for app image
FROM base

# Run as a non-root user
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint runs db:prepare (creates/migrates the tables in DATABASE_URL) before the server starts.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Render provides $PORT (10000 by default); Puma reads it from config/puma.rb.
EXPOSE 10000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]
