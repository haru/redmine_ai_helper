# frozen_string_literal: true
require_relative "logger"
require_relative "base_agent"
require_relative "langfuse_util/langfuse_wrapper"

module RedmineAiHelper

  # A class that is directly called from the controller to interact with AI using LLM.
  # TODO: Want to change class name
  class Llm
    include RedmineAiHelper::Logger
    attr_accessor :model

    def initialize(params = {})
    end

    # chat with the AI
    # @param conversation [Conversation] The conversation object
    # @param proc [Proc] A block to be executed after the task is sent
    # @param option [Hash] Options for the task
    # @return [AiHelperMessage] The AI's response
    def chat(conversation, proc, option = {})
      task = conversation.messages.last.content
      ai_helper_logger.debug "#### ai_helper: chat start ####"
      ai_helper_logger.info "user:#{User.current}, task: #{task}, option: #{option}"
      begin
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: task)
        option[:langfuse] = langfuse
        agent = RedmineAiHelper::Agents::LeaderAgent.new(option)
        langfuse.create_span(name: "user_request", input: task)
        answer = agent.perform_user_request(conversation.messages_for_openai, option, proc)
        langfuse.finish_current_span(output: answer)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        answer = e.message
      end
      ai_helper_logger.info "answer: #{answer}"
      AiHelperMessage.new(role: "assistant", content: answer, conversation: conversation)
    end

    # Get the summary of the issue using IssueAgent with streaming support
    # @param issue [Issue] The issue object
    # @param stream_proc [Proc] Optional callback proc for streaming content
    # return [String] The summary of the issue
    def issue_summary(issue:, stream_proc: nil)
      begin
        prompt = "Please summarize the issue #{issue.id}."
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        agent = RedmineAiHelper::Agents::IssueAgent.new(project: issue.project, langfuse: langfuse)
        langfuse.create_span(name: "user_request", input: prompt)
        answer = agent.issue_summary(issue: issue, stream_proc: stream_proc)
        langfuse.finish_current_span(output: answer)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        answer = e.message
        stream_proc.call(answer) if stream_proc
      end
      ai_helper_logger.info "answer: #{answer}"
      answer
    end

    # Generate a reply to the issue using IssueAgent with streaming support
    # @param issue [Issue] The issue object
    # @param instructions [String] Instructions for generating the reply
    # @param stream_proc [Proc] Optional callback proc for streaming content
    # return [String] The generated reply
    def generate_issue_reply(issue:, instructions:, stream_proc: nil)
      begin
        prompt = "Please generate a reply to the issue #{issue.id} with the instructions.\n\n#{instructions}"
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        agent = RedmineAiHelper::Agents::IssueAgent.new(project: issue.project, langfuse: langfuse)
        langfuse.create_span(name: "user_request", input: prompt)

        answer = agent.generate_issue_reply(issue: issue, instructions: instructions, stream_proc: stream_proc)

        langfuse.finish_current_span(output: answer)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        answer = e.message
        stream_proc.call(answer) if stream_proc
      end
      ai_helper_logger.info "answer: #{answer}"
      answer
    end

    # Generate sub issues using IssueAgent
    # @param issue [Issue] The issue object
    # @param instructions [String] Instructions for generating sub issues
    # return [Array<Issue>] The generated sub issues
    def generate_sub_issues(issue:, instructions: nil)
      begin
        prompt = "Please generate sub issues for the issue #{issue.id} with the instructions.\n\n#{instructions}"
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        agent = RedmineAiHelper::Agents::IssueAgent.new(project: issue.project, langfuse: langfuse)
        langfuse.create_span(name: "user_request", input: prompt)
        sub_issues = agent.generate_sub_issues_draft(issue: issue, instructions: instructions)
        langfuse.finish_current_span(output: sub_issues.inspect)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        throw e
      end
      ai_helper_logger.info "sub issues: #{sub_issues.inspect}"
      sub_issues
    end

    # Find similar issues using IssueAgent
    # @param issue [Issue] The issue object to find similar issues for
    # @return [Array<Hash>] Array of similar issues with metadata
    def find_similar_issues(issue:)
      begin
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: "find similar issues for #{issue.id}")
        agent = RedmineAiHelper::Agents::IssueAgent.new(project: issue.project, langfuse: langfuse)
        langfuse.create_span(name: "find_similar_issues", input: "issue_id: #{issue.id}")
        results = agent.find_similar_issues(issue: issue)
        langfuse.finish_current_span(output: results)
        langfuse.flush
        results
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        raise e
      end
    end

    # Get the summary of the wiki page using WikiAgent with streaming support
    # @param wiki_page [WikiPage] The wiki page object
    # @param stream_proc [Proc] Optional callback proc for streaming content
    # return [String] The summary of the wiki page
    def wiki_summary(wiki_page:, stream_proc: nil)
      begin
        prompt = "Please summarize the wiki page '#{wiki_page.title}'."
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        agent = RedmineAiHelper::Agents::WikiAgent.new(project: wiki_page.wiki.project, langfuse: langfuse)
        langfuse.create_span(name: "user_request", input: prompt)
        answer = agent.wiki_summary(wiki_page: wiki_page, stream_proc: stream_proc)
        langfuse.finish_current_span(output: answer)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        answer = e.message
        stream_proc.call(answer) if stream_proc
      end
      ai_helper_logger.info "answer: #{answer}"
      answer
    end

    # Generate project health report using ProjectAgent with streaming support
    # @param project [Project] The project object
    # @param stream_proc [Proc] Optional callback proc for streaming content
    # @return [String] The project health report
    def project_health_report(project:, stream_proc: nil)
      begin
        prompt = "project_health_report"

        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        options = {}
        options[:langfuse] = langfuse
        options[:project_id] = project.id
        agent = RedmineAiHelper::Agents::ProjectAgent.new(options)
        langfuse.create_span(name: "user_request", input: prompt)
        answer = agent.project_health_report(
          project: project,
          options: options,
          stream_proc: stream_proc,
        )
        langfuse.finish_current_span(output: answer)
        langfuse.flush
      rescue => e
        ai_helper_logger.error "error: #{e.full_message}"
        answer = e.message
        stream_proc.call(answer) if stream_proc
      end
      ai_helper_logger.info "project health report: #{answer}"
      answer
    end

    # Generate text completion for inline auto-completion
    # @param text [String] The current text content
    # @param cursor_position [Integer] The cursor position in the text
    # @param project [Project] The project object
    # @param wiki_page [WikiPage] Optional wiki page object for context
    # @param is_section_edit [Boolean] Whether this is a section edit
    # @return [String] The completion suggestion
    def generate_wiki_completion(text:, cursor_position: nil, project: nil, wiki_page: nil,
                                 is_section_edit: false)
      begin
        ai_helper_logger.info "Starting wiki completion: text='#{text[0..50]}...', cursor_position=#{cursor_position}, section_edit=#{is_section_edit}"

        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: text)
        options = { langfuse: langfuse, project: project }
        agent = RedmineAiHelper::Agents::WikiAgent.new(options)

        langfuse.create_span(name: "wiki_completion", input: text)

        completion = agent.generate_wiki_completion(
          text: text,
          cursor_position: cursor_position,
          project: project,
          wiki_page: wiki_page,
          is_section_edit: is_section_edit,
        )

        ai_helper_logger.info "WikiAgent returned completion: '#{completion}' (length: #{completion.length})"

        langfuse.finish_current_span(output: completion)
        langfuse.flush

        completion
      rescue => e
        ai_helper_logger.error "Wiki completion error: #{e.full_message}"
        ""
      end
    end

    # Generate text completion for inline auto-completion
    # @param text [String] The current text content
    # @param context_type [String] The context type (description, etc.)
    # @param cursor_position [Integer, nil] The cursor position in the text
    # @param project [Project, nil] The project object
    # @param issue [Issue, nil] Optional issue object for context
    # @return [String] The completion suggestion
    def generate_text_completion(text:, context_type:, cursor_position: nil, project: nil, issue: nil)
      begin
        ai_helper_logger.info "Starting text completion: text='#{text[0..50]}...', cursor_position=#{cursor_position}, context_type=#{context_type}"

        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: text)
        options = { langfuse: langfuse, project: project }
        agent = RedmineAiHelper::Agents::IssueAgent.new(options)

        langfuse.create_span(name: "text_completion", input: text)

        completion = agent.generate_text_completion(
          text: text,
          cursor_position: cursor_position,
          context_type: context_type,
          project: project,
          issue: issue,
        )

        ai_helper_logger.info "Agent returned completion: '#{completion}' (length: #{completion.length})"

        langfuse.finish_current_span(output: completion)
        langfuse.flush

        completion
      rescue => e
        ai_helper_logger.error "Text completion error: #{e.full_message}"
        ai_helper_logger.error e.backtrace.join("\n")
        # Return empty string on error to avoid breaking UI
        ""
      end
    end

    # Check text for typos using DocumentationAgent
    # @param text [String] The text to check
    # @param context_type [String] The context type
    # @param project [Project, nil] The project object
    # @param max_suggestions [Integer] Maximum number of suggestions to return
    # @return [Array<Hash>] Array of typo suggestions
    def check_typos(text:, context_type: 'general', project: nil, max_suggestions: 10)
      begin
        ai_helper_logger.info "Starting typo check: context_type=#{context_type}, text_length=#{text.length}"

        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: text)
        options = { langfuse: langfuse, project: project }
        agent = RedmineAiHelper::Agents::DocumentationAgent.new(options)

        langfuse.create_span(name: "typo_check", input: text)
        
        suggestions = agent.check_typos(
          text: text,
          context_type: context_type,
          max_suggestions: max_suggestions
        )
        
        ai_helper_logger.info "DocumentationAgent returned suggestions: #{suggestions}"
        
        langfuse.finish_current_span(output: suggestions)
        langfuse.flush
        
        suggestions
      rescue => e
        ai_helper_logger.error "Typo check error: #{e.full_message}"
        []
      end
    end

    private
  end
end
