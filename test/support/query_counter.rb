# Counts the SQL statements a block runs (ignores schema lookups and transaction control).
module QueryCounter
  IGNORED_NAMES = %w[SCHEMA TRANSACTION].freeze
  IGNORED_SQL = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i

  def count_queries
    queries = []
    callback = lambda do |*, payload|
      next if IGNORED_NAMES.include?(payload[:name]) || payload[:sql].match?(IGNORED_SQL)
      queries << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end
end
