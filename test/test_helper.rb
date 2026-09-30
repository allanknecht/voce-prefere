ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The layout links the compiled Tailwind stylesheet (app/assets/builds/tailwind.css, not
# committed). Build it once if it is missing so a fresh checkout can run `bin/rails test`.
unless Rails.root.join("app/assets/builds/tailwind.css").exist?
  system({ "RAILS_ENV" => "test" }, "bin/rails", "tailwindcss:build", chdir: Rails.root.to_s, exception: true)
end

require_relative "support/public_request_helper"
require_relative "support/production_boot"
require_relative "support/query_counter"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  include QueryCounter
  include PublicRequestHelper
end
