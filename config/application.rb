require_relative "boot"

require "rails"
# Only the frameworks this app actually uses (no Action Cable / Storage / Mailer / Job).
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
# require "rails/test_unit/railtie"

# Require the gems listed in the Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module VocePrefere
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # lib/ holds small plain-Ruby helpers (privacy logging, admin secret) that are
    # required explicitly from initializers, so it is not autoloaded.
    config.autoload_lib(ignore: %w[assets tasks privacy admin_secret.rb])

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
