# Controller for the AI Helper dashboard area, including health report history
# management and report exports.
class AiHelperDashboardController < ApplicationController
  include ActionController::Live
  include RedmineAiHelper::Logger
  include AiHelper::Streaming
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper

  protect_from_forgery

  before_action :find_project, :authorize, :find_user
  before_action :find_health_report_and_project, only: [:health_report_show, :health_report_destroy]
  before_action :set_per_page_limit, only: [:index]

  # Render the dashboard landing page for the current project.
  def index
  end

  # Display paginated health report history for the current project.
  def health_report_history
    @limit = per_page_option
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
      format.pdf do
        filename = "#{@project.identifier}-health-report-#{@health_report.created_at.strftime("%Y%m%d")}.pdf"
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
      format.html { redirect_to ai_helper_dashboard_path(@project, tab: "health_report"), notice: l(:notice_successful_delete) }
      format.json do
        render json: {
          status: "ok",
          deleted_report_id: report_id,
          message: l(:notice_successful_delete),
        }
      end
    end
  end

  # Health report comparison feature
  # GET  - Show comparison UI
  # POST - Execute streaming analysis
  def compare_health_reports
    if streaming_request?
      perform_streaming_comparison
    else
      show_comparison_ui
    end
  end

  # Export comparison analysis as PDF
  def comparison_pdf
    comparison_content = params[:comparison_content]
    old_report_id = params[:old_report_id]
    new_report_id = params[:new_report_id]

    if comparison_content.present?
      # Sanitize content - only allow Markdown, no HTML/JavaScript
      # Remove \r to prevent Loofah from encoding it as &#13; in text output
      # Use Loofah to safely remove dangerous elements (script, style, etc.) with their content
      sanitized_content = Loofah.fragment(comparison_content.delete("\r")).scrub!(:prune).to_text.strip

      filename = "#{@project.identifier}-health-report-comparison-#{Date.current.strftime("%Y%m%d")}.pdf"
      send_data(project_health_to_pdf(@project, sanitized_content),
                type: "application/pdf",
                filename: filename)
    else
      redirect_to ai_helper_health_report_compare_path(@project, old_id: old_report_id, new_id: new_report_id),
                  alert: t("ai_helper.project_health.no_report_available")
    end
  end

  # Export comparison analysis as Markdown
  def comparison_markdown
    comparison_content = params[:comparison_content]
    old_report_id = params[:old_report_id]
    new_report_id = params[:new_report_id]

    if comparison_content.present?
      # Sanitize content - only allow Markdown, no HTML/JavaScript
      # Remove \r to prevent Loofah from encoding it as &#13; in text output
      # Use Loofah to safely remove dangerous elements (script, style, etc.) with their content
      sanitized_content = Loofah.fragment(comparison_content.delete("\r")).scrub!(:prune).to_text.strip

      filename = "#{@project.identifier}-health-report-comparison-#{Date.current.strftime("%Y%m%d")}.md"
      send_data(sanitized_content,
                type: "text/markdown",
                filename: filename)
    else
      redirect_to ai_helper_health_report_compare_path(@project, old_id: old_report_id, new_id: new_report_id),
                  alert: t("ai_helper.project_health.no_report_available")
    end
  end

  private

  # Always enforce CSRF verification for this controller.
  # Overrides Redmine's ApplicationController which conditionally skips
  # verification for API requests. This controller does not serve API requests.
  def verify_authenticity_token
    unless verified_request?
      handle_unverified_request
    end
  end

  # Always handle unverified requests by returning 422.
  # Overrides Redmine's version which skips handling for API-format requests.
  def handle_unverified_request
    cookies.delete(autologin_cookie_name)
    self.logged_user = nil
    set_localization
    render_error status: 422, message: l(:error_invalid_authenticity_token)
  end

  # Show comparison UI
  def show_comparison_ui
    @old_report_id = params[:old_id]
    @new_report_id = params[:new_id]

    # Validate parameters
    if @old_report_id.blank? || @new_report_id.blank?
      flash[:error] = l("ai_helper.health_report_comparison.error_select_two_reports")
      redirect_to ai_helper_dashboard_path(@project, tab: "health_report")
      return
    end

    # Fetch reports
    @old_report = AiHelperHealthReport.find(@old_report_id)
    @new_report = AiHelperHealthReport.find(@new_report_id)

    # Check permissions
    unless @old_report.project_id == @project.id && @old_report.visible?(@user)
      render_403
      return
    end

    unless @new_report.project_id == @project.id && @new_report.visible?(@user)
      render_403
      return
    end

    # Ensure chronological order (old first)
    if @old_report.created_at > @new_report.created_at
      @old_report, @new_report = @new_report, @old_report
    end

    render template: "ai_helper/project/health_report_comparison"
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Execute streaming comparison analysis
  def perform_streaming_comparison
    old_report_id = params[:old_report_id]
    new_report_id = params[:new_report_id]

    old_report = AiHelperHealthReport.find(old_report_id)
    new_report = AiHelperHealthReport.find(new_report_id)

    # Check permissions
    unless old_report.visible?(@user) && new_report.visible?(@user)
      render_403
      return
    end

    unless old_report.project_id == @project.id && new_report.project_id == @project.id
      render_403
      return
    end

    begin
      llm = RedmineAiHelper::Llm.new

      stream_llm_response(close_stream: false) do |stream_proc|
        llm.compare_health_reports(
          old_report: old_report,
          new_report: new_report,
          project: @project,
          stream_proc: stream_proc,
        )
      end
    rescue => e
      ai_helper_logger.error "Health report comparison error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")

      prepare_streaming_headers

      write_chunk({
        id: "error-#{SecureRandom.hex(6)}",
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "error",
        choices: [{
          index: 0,
          delta: { content: "Error: #{e.message}" },
          finish_reason: "stop",
        }],
      })
    ensure
      response.stream.close
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def streaming_request?
    request.post? || request.headers["Accept"].to_s.include?("text/event-stream")
  end

  def set_per_page_limit
    @limit = per_page_option
  end

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
