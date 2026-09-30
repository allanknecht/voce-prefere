# Admin: manage ALL options (approved, pending, rejected).
#
# * Same admin-only access and session-based CSRF as the rest of the admin area (AdminArea +
#   AdminAuthentication); PATCH/DELETE carry Rails' authenticity token.
# * Edit goes through the same rules as a public submission: stripped text, 1..120 chars,
#   ContentModerator. Because this is an admin decision, a moderation hit is shown as a warning
#   and only saved when the admin ticks "forçar"; the status is not changed by an edit.
#   Duplicates (case/accent-insensitive) are refused, also with "forçar": it is never desirable.
# * Delete has a server-rendered confirmation page (works under the strict CSP, no JS) that
#   says how many votes go away, then removes the option and its votes in one transaction.
class AdminOptionsController < ApplicationController
  include AdminArea
  include AdminAuthentication

  PER_PAGE = 25

  before_action :set_option, only: %i[edit update confirm_destroy destroy]

  def index
    @status = Option::STATUS_FILTERS.key?(params[:status]) ? params[:status] : nil
    @query = params[:q].to_s.strip.first(120)

    ids = Option.admin_ids(status: @status, query: @query)
    @total = ids.size
    @total_pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)

    page_ids = ids.slice((@page - 1) * PER_PAGE, PER_PAGE) || []
    by_id = Option.where(id: page_ids).index_by(&:id)
    @options = page_ids.filter_map { |id| by_id[id] }
    @vote_counts = Vote.where(option_id: page_ids).group(:option_id).count
  end

  def edit
    @moderation_reasons = []
  end

  def update
    text = params.dig(:option, :text).to_s.strip
    force = params.dig(:option, :force) == "1"
    @option.text = text

    unless @option.valid?(:admin_edit)
      @moderation_reasons = []
      return render :edit, status: :unprocessable_entity
    end

    @moderation_reasons = ContentModerator.check(text)[:reasons]
    if @moderation_reasons.any? && !force
      @needs_force = true
      return render :edit, status: :unprocessable_entity
    end

    @option.save!(context: :admin_edit)
    redirect_to admin_options_path(list_params), notice: "Opção atualizada"
  end

  def confirm_destroy
    @votes_count = @option.related_votes.count
  end

  def destroy
    @option.destroy_with_votes!
    redirect_to admin_options_path(list_params), notice: "Opção excluída"
  end

  private

  def set_option
    @option = Option.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_options_path, alert: "Opção não encontrada"
  end

  # filter / search / page to come back to after an edit or delete
  def list_params
    params.permit(:status, :q, :page).to_h.symbolize_keys.compact_blank
  end
  helper_method :list_params
end
