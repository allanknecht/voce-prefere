require "open3"
require "tmpdir"

# Runs a snippet inside the real production environment (STDOUT logger, force_ssl,
# production middleware stack) in a subprocess, with a throwaway SQLite database
# standing in for Postgres, and returns its combined output.
module ProductionBoot
  module_function

  def run(script, env: {})
    Dir.mktmpdir do |dir|
      base_env = {
        "RAILS_ENV" => "production",
        "SECRET_KEY_BASE" => SecureRandom.hex(64),
        "ADMIN_SECRET" => SecureRandom.hex(16),
        "DATABASE_URL" => "sqlite3:#{dir}/prod.sqlite3",
        "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s
      }
      out, status = Open3.capture2e(base_env.merge(env), RbConfig.ruby, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      raise "production boot failed:\n#{out.lines.last(8).join}" unless status.success?
      out
    end
  end

  # Same, but returns [output, success?] without raising (used for the fail-fast tests).
  def attempt(script, env: {})
    Dir.mktmpdir do |dir|
      base_env = {
        "RAILS_ENV" => "production", "SECRET_KEY_BASE" => SecureRandom.hex(64),
        "DATABASE_URL" => "sqlite3:#{dir}/prod.sqlite3", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s
      }
      out, status = Open3.capture2e(base_env.merge(env), RbConfig.ruby, "bin/rails", "runner", script, chdir: Rails.root.to_s)
      [ out, status.success? ]
    end
  end
end
