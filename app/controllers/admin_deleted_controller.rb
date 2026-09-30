# Admin: read-only list (most recent first, 25 per page) of option texts that were deleted or
# rejected. No edit / delete actions.
class AdminDeletedController < ApplicationController
  include AdminArea
  include AdminAuthentication

  PER_PAGE = 25

  def index
    @total = DeletedOption.count
    @total_pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
    @page = params[:page].to_i.clamp(1, @total_pages)
    @entries = DeletedOption.recent_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
  end
end
