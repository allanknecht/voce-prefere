class AdminController < ApplicationController
  include AdminArea
  include AdminAuthentication

  PER_PAGE = 25

  def index
    @queue_count = Option.in_review.count
  end

  # Persistent review queue: new options (already on air), reported options (still on air) and
  # old off-air options waiting for a decision. Reported ones come first.
  def review
    @total = Option.in_review.count
    @total_pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @options = Option.in_review.review_order.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a
    @vote_counts = Vote.where(option_id: @options.map(&:id)).group(:option_id).count
  end

  def approve
    option = Option.find_by(id: params[:id])
    option&.approve!
    redirect_to admin_review_path, notice: option ? "Opção aprovada" : "Opção não encontrada"
  end
end
