class AiHelperDashboardController < ApplicationController
  include RedmineAiHelper::Logger
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper

  before_action :find_project, :authorize, :find_user
  before_action :find_health_report_and_project, only: [:health_report_show, :health_report_destroy]

  def index
  end

  def health_report_history
    @limit = 10 # Fixed page size for health reports
    @health_report_count = AiHelperHealthReport
      .for_project(@project.id)
      .visible
      .count
    @health_report_pages = Redmine::Pagination::Paginator.new @health_report_count, @limit, params[:page]
    @offset = @health_report_pages.offset
    @health_reports = AiHelperHealthReport
      .for_project(@project.id)
      .visible
      .sorted
      .limit(@limit)
      .offset(@offset)
      .to_a

    respond_to do |format|
      format.html { render partial: "ai_helper/project/health_report_history" }
      format.json { render json: @health_reports }
    end
  end

  def health_report_show
    unless @health_report.visible?
      render_403
      return
    end

    respond_to do |format|
      format.html { render template: "ai_helper/project/health_report_show", layout: "base" }
      format.pdf do
        filename = "#{@project.identifier}-health-report-#{@health_report.created_at.strftime('%Y%m%d')}.pdf"
        send_data(project_health_to_pdf(@project, @health_report.health_report),
                  type: "application/pdf",
                  filename: filename)
      end
    end
  end

  def health_report_destroy
    unless @health_report.deletable?
      render_403
      return
    end

    @health_report.destroy

    respond_to do |format|
      format.html { redirect_to ai_helper_dashboard_path(@project, tab: 'health_report'), notice: l(:notice_successful_delete) }
      format.json { render json: { status: 'ok' } }
    end
  end

  private

  def find_user
    @user = User.current
  end

  def find_health_report_and_project
    @health_report = AiHelperHealthReport.find(params[:report_id])
    @project = @health_report.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
