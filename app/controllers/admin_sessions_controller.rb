# Admin login.
#
# GET /admin/login is hit by anonymous visitors and scanners, so it must not set any cookie.
# Rails' session-based CSRF token would force a session cookie onto that page, so the one
# login POST is protected statelessly instead (see StatelessCsrf): same-origin check
# (Sec-Fetch-Site / Origin) + a signed, purpose-bound, 1-hour token embedded in the form as a
# hidden field, + the brute-force throttle. The session cookie (Path=/admin, HttpOnly,
# Secure, SameSite=Strict) is only issued after a correct password. Logout and the admin
# panel keep Rails' regular session-based CSRF.
class AdminSessionsController < ApplicationController
  include AdminArea
  include StatelessCsrf

  LOGIN_TOKEN_PURPOSE = :admin_login
  LOGIN_TOKEN_TTL = 1.hour

  skip_forgery_protection only: :create
  before_action :disable_session, only: %i[new create]
  before_action :verify_login_request, only: :create

  def new
    @login_token = generate_stateless_token(LOGIN_TOKEN_PURPOSE, LOGIN_TOKEN_TTL)
  end

  def create
    unless RateLimiter.check(request.remote_ip, :admin_login)
      render_login_form("Muitas tentativas. Aguarde um pouco.", :too_many_requests)
      return
    end

    # Constant-time comparison (of digests, so lengths do not leak either)
    if AdminSecret.matches?(params[:secret].to_s)
      request.session_options[:skip] = false # the session cookie is issued only now
      reset_session # prevent session fixation
      session[:admin_authenticated_at] = Time.current.to_i
      redirect_to admin_index_path
    else
      RateLimiter.record(request.remote_ip, :admin_login)
      render_login_form("Senha incorreta", :unauthorized)
    end
  end

  def destroy
    reset_session
    redirect_to root_path
  end

  private

  def disable_session
    request.session_options[:skip] = true
  end

  def verify_login_request
    return if same_origin_request? && valid_stateless_token?(params[:login_token], LOGIN_TOKEN_PURPOSE)

    head :unprocessable_entity
  end

  def render_login_form(error, status)
    @error = error
    @login_token = generate_stateless_token(LOGIN_TOKEN_PURPOSE, LOGIN_TOKEN_TTL)
    render :new, status: status
  end
end
