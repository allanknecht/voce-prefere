# Admin: manage ALL options.
#
# * Same admin-only access and session-based CSRF as the rest of the admin area (AdminArea +
#   AdminAuthentication); PATCH/DELETE carry Rails' authenticity token.
# * The admin can also change the good/bad category of an option (pairs are built per category).
# * Edit only validates: stripped text, 1..120 characters and no duplicate (case/accent
#   insensitive). There is NO content filter of any kind; the status is not changed by an edit.
# * Delete has a server-rendered confirmation page (works under the strict CSP, no JS) that
#   says how many votes go away, then removes the option and its votes in one transaction.
class AdminOptionsController < ApplicationController
  include AdminArea
  include AdminAuthentication

  PER_PAGE = 25

  before_action :set_option, only: %i[edit update confirm_destroy destroy]

  def index
    @status = Option::STATUS_FILTERS.key?(params[:status]) ? params[:status] : nil
    @category = Option::CATEGORY_FILTERS.key?(params[:category]) ? params[:category] : nil
    @query = params[:q].to_s.strip.first(120)

    ids = Option.admin_ids(status: @status, query: @query, category: @category)
    @total = ids.size
    @total_pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)

    page_ids = ids.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    by_id = Option.where(id: page_ids).index_by(&:id)
    @options = page_ids.filter_map { |id| by_id[id] }
    @vote_counts = Vote.where(option_id: page_ids).group(:option_id).count
  end

  def edit
  end

  def update
    @option.text = params.dig(:option, :text).to_s.strip
    @option.category = params.dig(:option, :category) if OptionClassifier::CATEGORIES.include?(params.dig(:option, :category))

    return render :edit, status: :unprocessable_entity unless @option.valid?(:admin_edit)

    @option.save!(context: :admin_edit)
    redirect_to admin_options_path(list_params), notice: "Opção atualizada"
  end

  def confirm_destroy
    @votes_count = @option.related_votes.count
    @from_review = from_review?
  end

  # Excluir. Coming from the review queue (?from=review) the deletion is logged as "excluída na
  # fila" and the admin goes back to the queue; otherwise it is "excluída manualmente".
  def destroy
    if from_review?
      @option.destroy_from_queue!
      redirect_to admin_review_path, notice: "Opção excluída"
    else
      @option.destroy_with_votes!
      redirect_to admin_options_path(list_params), notice: "Opção excluída"
    end
  end

  private

  def set_option
    @option = Option.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_options_path, alert: "Opção não encontrada"
  end

  def from_review?
    params[:from] == "review"
  end

  # filter / search / page to come back to after an edit or delete
  def list_params
    params.permit(:status, :category, :q, :page).to_h.symbolize_keys.compact_blank
  end
  helper_method :list_params
end
