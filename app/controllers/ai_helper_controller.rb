# frozen_string_literal: true
# This controller is responsible for handling the chat messages between the user and the AI.
require "redmine_ai_helper/llm"
require "redmine_ai_helper/logger"
require "redmine_ai_helper/export/pdf/project_health_pdf_helper"

# Controller for AI Helper plugin's main functionality
# Handles chat interactions, project health reports, issue summaries, and wiki completions
class AiHelperController < ApplicationController
  include ActionController::Live
  include RedmineAiHelper::Logger
  include AiHelper::Streaming
  include AiHelperHelper
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper

  protect_from_forgery except: [:generate_project_health, :suggest_completion, :suggest_wiki_completion, :check_typos]
  before_action :find_issue, only: [:issue_summary, :update_issue_summary, :generate_issue_summary, :generate_issue_reply, :generate_sub_issues, :add_sub_issues, :similar_issues]
  before_action :find_wiki_page, only: [:wiki_summary, :generate_wiki_summary]
  before_action :find_project, except: [:issue_summary, :wiki_summary, :generate_issue_summary, :generate_wiki_summary, :generate_issue_reply, :generate_sub_issues, :add_sub_issues, :similar_issues]
  before_action :find_user, :create_session, :find_conversation
  before_action :authorize

  # Display the chat form in the sidebar
  # @return [void]
  def chat_form
    @message = AiHelperMessage.new
    render partial: "ai_helper/chat/chat_form"
  end

  # Redisplay the chat screen
  # @return [void]
  def reload
    render partial: "ai_helper/chat/chat"
  end

  # Reflect the message entered in the chat form on the chat screen
  def chat
    @message = AiHelperMessage.new
    unless @conversation.id
      @conversation.title = "Chat with AI"
      @conversation.save!
      set_conversation_id(@conversation.id)
    end
    @message.conversation = @conversation
    @message.role = "user"
    @message.content = params[:ai_helper_message][:content]
    @message.save!
    @conversation = AiHelperConversation.find(@conversation.id)
    AiHelperConversation.cleanup_old_conversations
    render partial: "ai_helper/chat/chat"
  end

  # Load the specified conversation
  # If the request is a delete request, delete the conversation
  def conversation
    if request.delete?
      conversation = AiHelperConversation.find(params[:conversation_id])
      need_reload = conversation.id == @conversation.id
      conversation.destroy!
      session[:ai_helper] = {} if need_reload
      return render json: { status: "ok", reload: need_reload }
    end
    @conversation = AiHelperConversation.find(params[:conversation_id])
    set_conversation_id(@conversation.id)
    reload
  end

  # Display the conversation history
  def history
    @conversations = AiHelperConversation.where(user: @user).order(updated_at: :desc).limit(10)
    render partial: "ai_helper/chat/history"
  end

  # Display the issue summary
  def issue_summary
    summary = AiHelperSummaryCache.issue_cache(issue_id: @issue.id)
    if params[:update] == "true" && summary
      summary.destroy!
      summary = nil
    end

    render partial: "ai_helper/issues/summary", locals: { summary: summary }
  end

  # Generate issue summary with streaming
  def generate_issue_summary
    # Clear existing cache
    summary = AiHelperSummaryCache.issue_cache(issue_id: @issue.id)
    summary&.destroy!

    llm = RedmineAiHelper::Llm.new
    full_content = ""

    stream_llm_response do |stream_proc|
      # Wrap stream_proc to capture content for caching
      cache_proc = Proc.new do |content|
        full_content += content if content
        stream_proc.call(content)
      end

      content = llm.issue_summary(issue: @issue, stream_proc: cache_proc)
      # Update cache with final content
      AiHelperSummaryCache.update_issue_cache(issue_id: @issue.id, content: content)
    end
  end

  # Display the wiki summary
  def wiki_summary
    summary = AiHelperSummaryCache.wiki_cache(wiki_page_id: @wiki_page.id)
    if params[:update] == "true" && summary
      summary.destroy!
      summary = nil
    end
    llm = RedmineAiHelper::Llm.new
    unless summary
      content = llm.wiki_summary(wiki_page: @wiki_page)
      summary = AiHelperSummaryCache.update_wiki_cache(wiki_page_id: @wiki_page.id, content: content)
    end

    render partial: "ai_helper/wiki/summary_content", locals: { summary: summary }
  end

  # Generate wiki summary with streaming
  def generate_wiki_summary
    # Clear existing cache
    summary = AiHelperSummaryCache.wiki_cache(wiki_page_id: @wiki_page.id)
    summary&.destroy!

    llm = RedmineAiHelper::Llm.new
    full_content = ""

    stream_llm_response do |stream_proc|
      # Wrap stream_proc to capture content for caching
      cache_proc = Proc.new do |content|
        full_content += content if content
        stream_proc.call(content)
      end

      content = llm.wiki_summary(wiki_page: @wiki_page, stream_proc: cache_proc)
      # Update cache with final content
      AiHelperSummaryCache.update_wiki_cache(wiki_page_id: @wiki_page.id, content: content)
    end
  end

  # Call the LLM and stream the response
  def call_llm
    contoller_name = params[:controller_name]
    action_name = params[:action_name]
    content_id = params[:content_id].to_i unless params[:content_id].blank?
    additional_info = {}
    params[:additional_info].each do |key, value|
      additional_info[key] = value
    end
    llm = RedmineAiHelper::Llm.new
    option = {
      controller_name: contoller_name,
      action_name: action_name,
      content_id: content_id,
      project: @project,
      additional_info: additional_info,
    }

    stream_llm_response do |stream_proc|
      @conversation.messages << llm.chat(@conversation, stream_proc, option)
      @conversation.save!
      AiHelperConversation.cleanup_old_conversations
    end
  end

  # Clear the chat screen
  def clear
    session[:ai_helper] = {}
    find_conversation
    render partial: "ai_helper/chat/chat"
  end

  # Receives a POST message with application/json content to generate an issue reply with streaming
  def generate_issue_reply
    unless request.content_type == "application/json"
      render json: { error: "Unsupported Media Type" }, status: :unsupported_media_type and return
    end

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request and return
    end

    instructions = data["instructions"]
    llm = RedmineAiHelper::Llm.new

    stream_llm_response do |stream_proc|
      llm.generate_issue_reply(issue: @issue, instructions: instructions, stream_proc: stream_proc)
    end
  end

  # Generate sub-issues drafts for the given issue
  def generate_sub_issues
    llm = RedmineAiHelper::Llm.new
    unless request.content_type == "application/json"
      render json: { error: "Unsupported Media Type" }, status: :unsupported_media_type and return
    end

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request and return
    end

    instructions = data["instructions"]
    subissues = llm.generate_sub_issues(issue: @issue, instructions: instructions)

    trackers = @issue.allowed_target_trackers
    trackers = trackers.reject do |tracker|
      @issue.tracker_id != tracker.id && tracker.disabled_core_fields.include?("parent_issue_id")
    end
    trackers_options_for_select = trackers.collect { |t| [t.name, t.id] }

    versions = @issue.assignable_versions || []
    versions_options_for_select = versions.collect { |v| [v.name, v.id] }

    render partial: "ai_helper/issues/subissues/issues", locals: { issue: @issue, subissues: subissues, trackers_options_for_select: trackers_options_for_select, versions_options_for_select: versions_options_for_select }
  end

  # Add sub-issues to the current issue
  def add_sub_issues
    issues_param = params[:sub_issues]
    issues_param.each do |issue_param_array|
      issue_param = issue_param_array[1].permit(:subject, :description, :tracker_id, :check, :fixed_version_id)
      # Skip if the issue_param does not have the :check key or if it is false
      next unless issue_param[:check]
      issue = Issue.new
      issue.author = User.current
      issue.project = @issue.project
      issue.parent_id = @issue.id
      issue.subject = issue_param[:subject]
      issue.description = issue_param[:description]
      issue.tracker_id = issue_param[:tracker_id]
      issue.fixed_version_id = issue_param[:fixed_version_id] unless issue_param[:fixed_version_id].blank?
      # Save the issue and handle errors
      unless issue.save
        # If saving fails, collect error messages and display them using i18n
        flash[:error] = issue.errors.full_messages.join("\n")
        redirect_to issue_path(@issue) and return
      end
    end
    redirect_to issue_path(@issue), notice: l(:notice_sub_issues_added)
  end

  # Find similar issues using LLM and IssueAgent
  def similar_issues
    begin
      llm = RedmineAiHelper::Llm.new
      similar_issues = llm.find_similar_issues(issue: @issue)

      render partial: "ai_helper/issues/similar_issues", locals: { similar_issues: similar_issues }
    rescue => e
      ai_helper_logger.error "Similar issues search error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  # Suggest auto-completion for textarea input
  def suggest_completion
    unless request.content_type == "application/json"
      render json: { error: "Unsupported Media Type" }, status: :unsupported_media_type and return
    end

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request and return
    end

    text = data["text"]
    context_type = data["context_type"] || "description" # "description" or "note"
    cursor_position = data["cursor_position"]

    # Input validation
    if text.blank?
      render json: { error: "Text is required" }, status: :bad_request and return
    end

    if text.length > 5000
      render json: { error: "Text too long" }, status: :bad_request and return
    end

    if cursor_position && (cursor_position < 0 || cursor_position > text.length)
      render json: { error: "Invalid cursor position" }, status: :bad_request and return
    end

    # Validate context_type
    unless %w[description note].include?(context_type)
      render json: { error: "Invalid context_type. Must be 'description' or 'note'" }, status: :bad_request and return
    end

    # Handle issue context
    issue = nil
    if params[:issue_id] != "new"
      issue = Issue.find_by(id: params[:issue_id])
      # Verify issue belongs to the project
      if issue && issue.project != @project
        render json: { error: "Issue does not belong to the specified project" }, status: :bad_request and return
      end
    end

    # Note completion requires an existing issue
    if context_type == "note" && !issue
      render json: { error: "Issue is required for note completion" }, status: :bad_request and return
    end

    # Debug logging
    ai_helper_logger.info "Auto-completion request: issue_id=#{params[:issue_id]}, context_type=#{context_type}, project=#{@project&.identifier}, user=#{User.current.id}"

    begin
      llm = RedmineAiHelper::Llm.new
      suggestion = llm.generate_text_completion(
        text: text,
        context_type: context_type,
        cursor_position: cursor_position,
        project: @project,
        issue: issue,
      )

      response_data = { suggestion: suggestion }
      render json: response_data
    rescue => e
      ai_helper_logger.error "Auto-completion error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")
      render json: { error: "Failed to generate suggestion" }, status: :internal_server_error
    end
  end

  # Generate wiki completion suggestions via JSON API
  # @return [void]
  def suggest_wiki_completion
    unless request.content_type == "application/json"
      render json: { error: "Unsupported Media Type" }, status: :unsupported_media_type and return
    end

    begin
      data = JSON.parse(request.body.read)
    rescue JSON::ParserError
      render json: { error: "Invalid JSON" }, status: :bad_request and return
    end

    text = data["text"]
    cursor_position = data["cursor_position"]

    if text.blank?
      render json: { error: "Text is required" }, status: :bad_request and return
    end

    if text.length > 10000
      render json: { error: "Text too long" }, status: :bad_request and return
    end

    if cursor_position && (cursor_position < 0 || cursor_position > text.length)
      render json: { error: "Invalid cursor position" }, status: :bad_request and return
    end

    # Section edit detection (section number is not sent)
    is_section_edit = data["is_section_edit"] || false

    # Debug log for tests
    ai_helper_logger.info "Wiki completion: is_section_edit from data: #{data["is_section_edit"].inspect}, final value: #{is_section_edit}"

    wiki_page = nil

    if params[:page_name].present? && @project
      wiki_page = @project.wiki&.find_page(params[:page_name])
    end

    begin
      llm = RedmineAiHelper::Llm.new
      suggestion = llm.generate_wiki_completion(
        text: text,
        cursor_position: cursor_position,
        project: @project,
        wiki_page: wiki_page,
        is_section_edit: is_section_edit,
      )

      response_data = { suggestion: suggestion }
      render json: response_data
    rescue => e
      ai_helper_logger.error "Wiki auto-completion error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")
      render json: { error: "Failed to generate suggestion" }, status: :internal_server_error
    end
  end

  # Display project health report
  # @return [void]
  def project_health
    cache_key = "project_health_#{@project.id}_#{params[:version_id]}_#{params[:start_date]}_#{params[:end_date]}"
    fetch_health_report = Proc.new do
      Rails.cache.fetch(cache_key, expires_in: 1.hour) do
        generate_project_health_report
      end
    end

    respond_to do |format|
      format.html do
        @health_report = fetch_health_report.call
        render partial: "ai_helper/project/health_report", locals: { health_report: @health_report }
      end
      format.pdf do
        @health_report = fetch_health_report.call
        if @health_report && !@health_report.is_a?(Hash)
          filename = "#{@project.identifier}-health-report-#{Date.current.strftime("%Y%m%d")}.pdf"
          send_data(project_health_to_pdf(@project, @health_report),
                    type: "application/pdf",
                    filename: filename)
        else
          redirect_to project_path(@project), alert: l(:label_ai_helper_no_report_available, default: "No health report available for PDF export")
        end
      end
    end
  end

  # Return metadata about the most recent health report for the current project.
  # @return [void]
  def project_health_metadata
    latest_report = AiHelperHealthReport.for_project(@project.id).sorted.first
    latest_report = nil unless latest_report&.visible?(User.current)

    if latest_report
      render json: {
        id: latest_report.id,
        created_at: latest_report.created_at,
        created_at_iso8601: latest_report.created_at&.iso8601,
        created_on_formatted: view_context.format_time(latest_report.created_at)
      }
    else
      head :no_content
    end
  end

  # Generate PDF from current health report content
  # @return [void]
  def project_health_pdf
    health_report_content = params[:health_report_content]

    if health_report_content.present?
      # Validate and sanitize content - only allow Markdown, no HTML/JavaScript
      # Remove any potential script tags or dangerous HTML while preserving Markdown
      sanitized_content = health_report_content.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, "")
                                               .gsub(/<[^>]*>/, "")

      filename = "#{@project.identifier}-health-report-#{Date.current.strftime("%Y%m%d")}.pdf"
      send_data(project_health_to_pdf(@project, sanitized_content),
                type: "application/pdf",
                filename: filename)
    else
      redirect_to project_path(@project), alert: t("ai_helper.project_health.no_report_available")
    end
  end

  # Generate Markdown from current health report content
  # @return [void]
  def project_health_markdown
    health_report_content = params[:health_report_content]

    if health_report_content.present?
      # Validate and sanitize content - only allow Markdown, no HTML/JavaScript
      # Remove any potential script tags or dangerous HTML while preserving Markdown
      sanitized_content = health_report_content.gsub(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/mi, "")
                                               .gsub(/<[^>]*>/, "")

      filename = "#{@project.identifier}-health-report-#{Date.current.strftime("%Y%m%d")}.md"
      send_data(sanitized_content,
                type: "text/markdown",
                filename: filename)
    else
      redirect_to project_path(@project), alert: t("ai_helper.project_health.no_report_available")
    end
  end

  # Generate project health report with streaming
  # @return [void]
  def generate_project_health
    ai_helper_logger.info "Starting project health generation for project #{@project.id}"
    cache_key = "project_health_#{@project.id}"
    Rails.cache.delete(cache_key)

    begin
      llm = RedmineAiHelper::Llm.new
      full_content = ""

      stream_llm_response do |stream_proc|
        cache_proc = Proc.new do |content|
          full_content += content if content
          stream_proc.call(content)
        end

        content = llm.project_health_report(
          project: @project,
          stream_proc: cache_proc,
        )

        Rails.cache.write(cache_key, content, expires_in: 1.hour)
      end
    rescue => e
      ai_helper_logger.error "Generate project health error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")

      # Send error as streaming response
      prepare_streaming_headers

      write_chunk({
        id: "error-#{SecureRandom.hex(6)}",
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "error",
        choices: [{
          index: 0,
          delta: {
            content: "Error generating project health report: #{e.message}",
          },
          finish_reason: "stop",
        }],
      })

      response.stream.close
    end
  end

  # Check text for typos
  # @return [void]
  def check_typos
    text = params[:text]
    return render json: { suggestions: [] } if text.blank?

    context_type = params[:context_type] || 'general'

    llm = RedmineAiHelper::Llm.new
    suggestions = llm.check_typos(
      text: text,
      context_type: context_type,
      project: @project,
      max_suggestions: 10
    )

    render json: { suggestions: suggestions }
  end

  private

  # Find the user
  def find_user
    @user = User.current
  end

  # Create a hash to store AI helper information in the session
  def create_session
    session[:ai_helper] ||= {}
  end

  # Retrieve the current conversation ID from the session
  def conversation_id
    session[:ai_helper][:conversation_id]
  end

  # Set the conversation ID in the session
  def set_conversation_id(id)
    session[:ai_helper][:conversation_id] = id
  end

  # Retrieve the conversation from the session-stored conversation ID.
  # If the conversation does not exist, create a new one.
  def find_conversation
    if conversation_id
      @conversation = AiHelperConversation.find_by(id: conversation_id)
      return if @conversation
    end
    @conversation = AiHelperConversation.new
    @conversation.user = @user
  end

  # Find wiki page for wiki summary
  def find_wiki_page
    @wiki_page = WikiPage.find(params[:id])
    @project = @wiki_page.wiki.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # Generate project health report data
  def generate_project_health_report
    llm = RedmineAiHelper::Llm.new
    llm.project_health_report(
      project: @project,
      version_id: params[:version_id],
      start_date: params[:start_date],
      end_date: params[:end_date],
    )
  rescue => e
    ai_helper_logger.error "Project health report error: #{e.message}"
    ai_helper_logger.error e.backtrace.join("\n")
    { error: e.message }
  end

end
