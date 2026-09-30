class AdminSessionsController < ApplicationController
  include AdminArea

  def new
  end

  def create
    unless RateLimiter.check(request.remote_ip, :admin_login)
      flash.now[:error] = "Muitas tentativas. Aguarde um pouco."
      render :new, status: :too_many_requests
      return
    end

    # Constant-time comparison (of digests, so lengths do not leak either)
    if AdminSecret.matches?(params[:secret].to_s)
      reset_session # prevent session fixation
      session[:admin_authenticated_at] = Time.current.to_i
      redirect_to admin_index_path
    else
      RateLimiter.record(request.remote_ip, :admin_login)
      flash.now[:error] = "Senha incorreta"
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to root_path
  end
end
