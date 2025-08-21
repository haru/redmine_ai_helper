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
    # @param version_id [Integer] Optional version ID to filter metrics
    # @param start_date [String] Optional start date for metrics
    # @param end_date [String] Optional end date for metrics
    # @param stream_proc [Proc] Optional callback proc for streaming content
    # @return [String] The project health report
    def project_health_report(project:, version_id: nil, start_date: nil, end_date: nil, stream_proc: nil)
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
    # @param context_type [String] The context type (description, etc.)
    # @param cursor_position [Integer] The cursor position in the text
    # @param project [Project] The project object
    # @param issue [Issue] Optional issue object for context
    # @return [String] The completion suggestion
    def generate_text_completion(text:, context_type:, cursor_position: nil, project: nil, issue: nil)
      begin
        ai_helper_logger.info "Starting text completion: text='#{text[0..50]}...', cursor_position=#{cursor_position}"
        
        context = build_completion_context(text, context_type, project, issue)
        ai_helper_logger.info "Built context: #{context}"
        
        prompt = build_inline_completion_prompt(text, context, cursor_position)
        ai_helper_logger.info "Built prompt: '#{prompt[0..200]}#{'...' if prompt.length > 200}'"
        
        langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: prompt)
        options = { langfuse: langfuse, project: project }
        agent = RedmineAiHelper::Agents::IssueAgent.new(options)
        
        langfuse.create_span(name: "text_completion", input: prompt)
        
        # Use the agent to generate completion with a special prompt
        completion = agent.generate_text_completion(
          text: text,
          cursor_position: cursor_position,
          context: context
        )
        
        ai_helper_logger.info "Agent returned raw completion: '#{completion}' (length: #{completion.length})"
        
        suggestion = parse_single_suggestion(completion)
        
        ai_helper_logger.info "Parsed final suggestion: '#{suggestion}' (length: #{suggestion.length})"
        
        langfuse.finish_current_span(output: suggestion)
        langfuse.flush
        
        suggestion
      rescue => e
        ai_helper_logger.error "Text completion error: #{e.full_message}"
        ai_helper_logger.error e.backtrace.join("\n")
        # Return empty string on error to avoid breaking UI
        ""
      end
    end

    private

    # Build context for completion based on project and issue information
    # @param text [String] The current text
    # @param context_type [String] The context type
    # @param project [Project] The project object
    # @param issue [Issue] The issue object
    # @return [Hash] Context information
    def build_completion_context(text, context_type, project, issue)
      context = {
        context_type: context_type,
        project_name: project&.name,
        issue_title: issue&.subject,
        text_length: text.length
      }
      
      # Add project-specific context if available
      if project
        context[:project_description] = project.description if project.description.present?
        context[:project_identifier] = project.identifier
      end
      
      context
    end

    # Build the prompt for inline completion
    # @param text [String] The current text
    # @param context [Hash] Context information
    # @param cursor_position [Integer] Cursor position
    # @return [String] The formatted prompt
    def build_inline_completion_prompt(text, context, cursor_position)
      config = load_autocompletion_config
      max_sentences = config['max_sentences'] || 3
      
      prefix_text = cursor_position ? text[0...cursor_position] : text
      suffix_text = (cursor_position && cursor_position < text.length) ? text[cursor_position..-1] : ""
      
      # Load prompt template
      locale = User.current.language || 'en'
      template_key = locale == 'ja' ? 'ja' : 'en'
      
      template = load_prompt_template('inline_completion', template_key)
      
      # Replace placeholders in template
      template.gsub('{issue_title}', context[:issue_title] || 'New Issue')
              .gsub('{prefix_text}', prefix_text)
              .gsub('{suffix_text}', suffix_text)
              .gsub('{project_name}', context[:project_name] || 'Unknown Project')
              .gsub('{cursor_position}', cursor_position.to_s)
              .gsub('{max_sentences}', max_sentences.to_s)
    end

    # Load autocompletion configuration
    # @return [Hash] Configuration hash
    def load_autocompletion_config
      @autocompletion_config ||= begin
        config_path = Rails.root.join('plugins', 'redmine_ai_helper', 'config', 'ai_helper', 'config.yml')
        if File.exist?(config_path)
          config_data = YAML.load_file(config_path)
          config_data['autocompletion'] || {}
        else
          {}
        end
      end
    end

    # Load prompt template
    # @param template_name [String] Template name
    # @param locale [String] Locale code
    # @return [String] Prompt template
    def load_prompt_template(template_name, locale)
      template_path = Rails.root.join('plugins', 'redmine_ai_helper', 'assets', 'prompt_templates', "#{template_name}.yml")
      if File.exist?(template_path)
        template_data = YAML.load_file(template_path)
        template_data[template_name] && template_data[template_name][locale] || ""
      else
        # Fallback template
        case locale
        when 'ja'
          "カーソル位置からテキストを短く補完してください（最大3文）: {prefix_text}|{suffix_text}"
        else
          "Complete the text from cursor position (max 3 sentences): {prefix_text}|{suffix_text}"
        end
      end
    end

    # Parse single suggestion from LLM response
    # @param response [String] The LLM response
    # @return [String] Clean suggestion text
    def parse_single_suggestion(response)
      return "" if response.blank?
      
      # Clean up the response - remove any markdown, extra whitespace, etc.
      cleaned = response.strip
      
      # Remove any potential markdown formatting
      cleaned = cleaned.gsub(/^\*+\s*/, '')  # Remove bullet points
      cleaned = cleaned.gsub(/^#+\s*/, '')   # Remove headers
      cleaned = cleaned.gsub(/\*\*(.*?)\*\*/, '\\1')  # Remove bold
      cleaned = cleaned.gsub(/\*(.*?)\*/, '\\1')      # Remove italic
      
      # Limit to reasonable length (max 3 sentences as per spec)
      sentences = cleaned.split(/[.!?]+/)
      if sentences.length > 3
        cleaned = sentences[0..2].join('. ').strip
        cleaned += '.' unless cleaned.end_with?('.', '!', '?')
      end
      
      cleaned
    end
  end
end
