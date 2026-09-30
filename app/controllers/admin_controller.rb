class AdminController < ApplicationController
  include AdminArea
  include AdminAuthentication

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
end
