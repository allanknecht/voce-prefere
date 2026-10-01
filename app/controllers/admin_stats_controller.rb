# Admin: first-party statistics (no personal data, see PRIVACY.md). Server-rendered, no JS charts.
class AdminStatsController < ApplicationController
  include AdminArea
  include AdminAuthentication

  def index
    @report = Analytics::Report.new(days: params[:dias])
  end
end
