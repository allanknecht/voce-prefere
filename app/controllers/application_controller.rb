class ApplicationController < ActionController::Base
  # Only allow modern browsers (CSS nesting, :has, ...).
  allow_browser versions: :modern
end
