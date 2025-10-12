# Controller for the AI Helper dashboard area, including health report history
# management and report exports.
class AiHelperDashboardController < ApplicationController
  include RedmineAiHelper::Logger
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper

  before_action :find_project, :authorize, :find_user
  before_action :find_health_report_and_project, only: [:health_report_show, :health_report_destroy]

  # Render the dashboard landing page for the current project.
  def index
  end

  # Display paginated health report history for the current project.
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

    # Determine which report should be selected (from URL params or default to most recent)
    @selected_report = if params[:report_id]
      @health_reports.find { |r| r.id.to_s == params[:report_id].to_s }
    else
      @health_reports.first
    end

    respond_to do |format|
      format.html { render partial: "ai_helper/project/health_report_history" }
      format.json { render json: @health_reports }
    end
  end

  # Show a specific health report and provide export options.
  def health_report_show
    unless @health_report.visible?(@user)
      render_403
      return
    end

    respond_to do |format|
      format.html { render template: "ai_helper/project/health_report_show", layout: "base" }
      format.json do
        render json: {
          id: @health_report.id,
          created_at: @health_report.created_at,
          user: {
            id: @health_report.user.id,
            name: @health_report.user.name
          },
          health_report: @health_report.health_report,
          formatted_html: view_context.textilizable(@health_report.health_report.to_s, object: @project)
        }
      end
      format.pdf do
        filename = "#{@project.identifier}-health-report-#{@health_report.created_at.strftime('%Y%m%d')}.pdf"
        send_data(project_health_to_pdf(@project, @health_report.health_report),
                  type: "application/pdf",
                  filename: filename)
      end
    end
  end

  # Delete a stored health report if the current user has permission.
  def health_report_destroy
    unless @health_report.deletable?(@user)
      render_403
      return
    end

    report_id = @health_report.id
    @health_report.destroy

    respond_to do |format|
      format.html { redirect_to ai_helper_dashboard_path(@project, tab: 'health_report'), notice: l(:notice_successful_delete) }
      format.json do
        render json: {
          status: 'ok',
          deleted_report_id: report_id,
          message: l(:notice_successful_delete)
        }
      end
    end
  end

  private

  def find_user
    @user = User.current
  end

  def find_health_report_and_project
    @health_report = AiHelperHealthReport.find(params[:report_id])
    # Verify the health report belongs to the current project
    unless @health_report.project_id == @project.id
      render_404
      return
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
