# Shared behaviour for the admin area. Unlike the public pages, admin uses a
# (short-lived, Path=/admin, Secure, HttpOnly, SameSite=Strict) session cookie and
# Rails' regular session-based CSRF protection.
module AdminArea
  extend ActiveSupport::Concern

  included do
    protect_from_forgery with: :exception
    before_action :no_store
  end

  private

  def no_store
    response.headers["Cache-Control"] = "no-store"
  end
end
