# Controller for the AI Helper dashboard area, including health report history
# management and report exports.
class AiHelperDashboardController < ApplicationController
  include ActionController::Live
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

  # Health report comparison feature
  # GET  - Show comparison UI
  # POST - Execute streaming analysis
  def compare_health_reports
    if request.post?
      perform_streaming_comparison
    else
      show_comparison_ui
    end
  end

  private

  # Show comparison UI
  def show_comparison_ui
    @old_report_id = params[:old_id]
    @new_report_id = params[:new_id]

    # Validate parameters
    if @old_report_id.blank? || @new_report_id.blank?
      flash[:error] = l('ai_helper.health_report_comparison.error_select_two_reports')
      redirect_to ai_helper_dashboard_path(@project, tab: 'health_report')
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

    render template: 'ai_helper/project/health_report_comparison'
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

    # Stream via Server-Sent Events
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Connection'] = 'keep-alive'

    begin
      llm = RedmineAiHelper::Llm.new

      stream_llm_response do |stream_proc|
        llm.compare_health_reports(
          old_report: old_report,
          new_report: new_report,
          project: @project,
          stream_proc: stream_proc
        )
      end
    rescue => e
      ai_helper_logger.error "Health report comparison error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")

      write_chunk({
        id: "error-#{SecureRandom.hex(6)}",
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "error",
        choices: [{
          index: 0,
          delta: { content: "Error: #{e.message}" },
          finish_reason: "stop"
        }]
      })
    ensure
      response.stream.close
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def write_chunk(data)
    response.stream.write("data: #{data.to_json}\n\n")
  end

  def stream_llm_response(&block)
    # Set up streaming response headers
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["Connection"] = "keep-alive"

    response_id = "chatcmpl-#{SecureRandom.hex(12)}"

    # Send initial chunk
    write_chunk({
      id: response_id,
      object: "chat.completion.chunk",
      created: Time.now.to_i,
      model: "gpt-3.5-turbo-0613",
      choices: [{
        index: 0,
        delta: {
          role: "assistant",
        },
        finish_reason: nil,
      }],
    })

    # Define streaming callback
    stream_proc = Proc.new do |content|
      write_chunk({
        id: response_id,
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "gpt-3.5-turbo-0613",
        choices: [{
          index: 0,
          delta: {
            content: content,
          },
          finish_reason: nil,
        }],
      })
    end

    # Execute the provided block with the streaming proc
    block.call(stream_proc)

    # Send completion chunk
    write_chunk({
      id: response_id,
      object: "chat.completion.chunk",
      created: Time.now.to_i,
      model: "gpt-3.5-turbo-0613",
      choices: [{
        index: 0,
        delta: {},
        finish_reason: "stop",
      }],
    })
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
