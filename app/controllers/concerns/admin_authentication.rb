# Admin-only access (session cookie issued after a successful login, 1 h sliding expiry).
module AdminAuthentication
  extend ActiveSupport::Concern

  SESSION_TTL = 1.hour

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    authenticated_at = session[:admin_authenticated_at].to_i

    if authenticated_at.positive? && (Time.current.to_i - authenticated_at) < SESSION_TTL.to_i
      session[:admin_authenticated_at] = Time.current.to_i # sliding expiry
    else
      reset_session if session[:admin_authenticated_at] # nothing to clear (and no cookie to send) otherwise
      redirect_to admin_login_path
    end
  end
end
