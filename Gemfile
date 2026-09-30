source "https://rubygems.org"

gem "rails", "~> 8.1.4"
# Asset pipeline (serves the plain JS file and the compiled Tailwind CSS)
gem "propshaft"
gem "tailwindcss-rails"
# Web server
gem "puma", ">= 5.0"
# PostgreSQL (Neon, Render Postgres, ...) in production via DATABASE_URL
gem "pg", "~> 1.5"
# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

group :development, :test do
  # SQLite is only used for local development and tests
  gem "sqlite3", ">= 2.1"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end
