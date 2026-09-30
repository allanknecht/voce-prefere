class AdminController < ApplicationController
  include AdminArea

  SESSION_TTL = 1.hour

  before_action :authenticate_admin!

  def index
    @pending_options = Option.pending.order(created_at: :desc)
    @reported_options = Option.reported.order(report_count: :desc, created_at: :desc)
  end

  def approve
    Option.find(params[:id]).approve!
    redirect_to admin_index_path, notice: "Opção aprovada"
  end

  def reject
    Option.find(params[:id]).reject!
    redirect_to admin_index_path, notice: "Opção rejeitada"
  end

  private

  def authenticate_admin!
    authenticated_at = session[:admin_authenticated_at].to_i

    if authenticated_at.positive? && (Time.current.to_i - authenticated_at) < SESSION_TTL.to_i
      session[:admin_authenticated_at] = Time.current.to_i # sliding expiry
    else
      reset_session
      redirect_to admin_login_path
    end
  end
end
