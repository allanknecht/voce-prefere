class AdminController < ApplicationController
  include AdminArea
  include AdminAuthentication

  PER_PAGE = 25

  def index
    @queue_count = Option.in_review.count
  end

  # Persistent review queue: new options (already on air) and options taken off air by reports.
  def review
    @total = Option.in_review.count
    @total_pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @options = Option.in_review.order(:created_at, :id).offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @vote_counts = Vote.where(option_id: @options.map(&:id)).group(:option_id).count
  end

  def approve
    option = Option.find_by(id: params[:id])
    option&.approve!
    redirect_to admin_review_path, notice: option ? "Opção aprovada" : "Opção não encontrada"
  end

  # Reprovar = delete for good (with its votes), text kept in deleted_options
  def reject
    option = Option.find_by(id: params[:id])
    option&.reject!
    redirect_to admin_review_path, notice: option ? "Opção reprovada e excluída" : "Opção não encontrada"
  end
end
