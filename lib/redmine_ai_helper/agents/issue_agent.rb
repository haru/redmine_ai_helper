# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # IssueAgent is a specialized agent for handling Redmine issue-related queries.
    class IssueAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Util::IssueJson
      include Rails.application.routes.url_helpers

      # Backstory for the IssueAgent
      def backstory
        search_answer_instruction = I18n.t("ai_helper.prompts.issue_agent.search_answer_instruction")
        search_answer_instruction = "" if AiHelperSetting.vector_search_enabled?
        prompt = load_prompt("issue_agent/backstory")
        prompt.format(issue_properties: issue_properties, search_answer_instruction: search_answer_instruction)
      end

      # Returns the list of available tool providers for the IssueAgent.
      def available_tool_providers
        base_tools = [
          RedmineAiHelper::Tools::IssueTools,
          RedmineAiHelper::Tools::ProjectTools,
          RedmineAiHelper::Tools::UserTools,
          RedmineAiHelper::Tools::IssueSearchTools,
        ]
        if AiHelperSetting.vector_search_enabled?
          base_tools.unshift(RedmineAiHelper::Tools::VectorTools)
        end

        base_tools
      end

      # Generate a summary of the issue with optional streaming support.
      # @param issue [Issue] The issue for which the summary is to be generated.
      # @param stream_proc [Proc] Optional callback proc for streaming content.
      # @return [String] The generated summary of the issue.
      # @raise [PermissionDenied] if the issue is not visible to the user.
      def issue_summary(issue:, stream_proc: nil)
        return "Permission denied" unless issue.visible?

        prompt = load_prompt("issue_agent/summary")
        issue_json = generate_issue_data(issue)
        prompt_text = prompt.format(issue: JSON.pretty_generate(issue_json))
        message = { role: "user", content: prompt_text }
        messages = [message]
        
        chat(messages, {}, stream_proc)
      end

      # Generate issue reply with optional streaming support
      # @param issue [Issue] The issue to base the reply on.
      # @param instructions [String] Instructions for generating the reply.
      # @param stream_proc [Proc] Optional callback proc for streaming content.
      # @return [String] The generated reply.
      # @raise [PermissionDenied] if the issue is not visible to the user.
      def generate_issue_reply(issue:, instructions:, stream_proc: nil)
        return "Permission denied" unless issue.visible?
        return "Permission denied" unless issue.notes_addable?(User.current)

        prompt = load_prompt("issue_agent/generate_reply")
        project_setting = AiHelperProjectSetting.settings(issue.project)
        issue_json = generate_issue_data(issue)
        prompt_text = prompt.format(
          issue: JSON.pretty_generate(issue_json),
          instructions: instructions,
          issue_draft_instructions: project_setting.issue_draft_instructions,
          format: Setting.text_formatting,
        )
        message = { role: "user", content: prompt_text }
        messages = [message]
        
        chat(messages, {}, stream_proc)
      end

      # Generate a draft for sub-issues based on the provided issue and instructions.
      # @param issue [Issue] The issue to base the sub-issues on.
      # @param instructions [String] Instructions for generating the sub-issues draft.
      # @return [Issue[]] An array of generated sub-issues. Not yet saved.
      # @raise [PermissionDenied] if the issue is not visible to the user.
      def generate_sub_issues_draft(issue:, instructions: nil)
        return "Permission denied" unless issue.visible?
        return "Permission denied" unless User.current.allowed_to?(:add_issues, issue.project)

        prompt = load_prompt("issue_agent/sub_issues_draft")
        json_schema = {
          type: "object",
          properties: {
            sub_issues: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  subject: {
                    type: "string",
                    description: "The subject of the sub-issue",
                  },
                  description: {
                    type: "string",
                    description: "The description of the sub-issue",
                  },
                  project_id: {
                    type: "integer",
                    description: "The ID of the project to which the sub-issue belongs",
                  },
                  tracker_id: {
                    type: "integer",
                    description: "The ID of the tracker for the sub-issue",
                  },
                  priority_id: {
                    type: "integer",
                    description: "The ID of the priority for the sub-issue",
                  },
                  fixed_version_id: {
                    type: "integer",
                    description: "The ID of the fixed version for the sub-issue",
                  },
                  due_date: {
                    type: "string",
                    format: "date",
                    description: "The due date for the sub-issue. YYYY-MM-DD format",
                  },
                },
                required: ["subject", "description", "project_id", "tracker_id"],
              },
            },
          },
        }
        parser = Langchain::OutputParsers::StructuredOutputParser.from_json_schema(json_schema)
        issue_json = generate_issue_data(issue)
        project_setting = AiHelperProjectSetting.settings(issue.project)

        prompt_text = prompt.format(
          parent_issue: JSON.pretty_generate(issue_json),
          instructions: instructions,
          subtask_instructions: project_setting.subtask_instructions,
          format_instructions: parser.get_format_instructions,
        )
        ai_helper_logger.debug "prompt_text: #{prompt_text}"

        message = { role: "user", content: prompt_text }
        messages = [message]
        answer = chat(messages, output_parser: parser)
        fix_parser = Langchain::OutputParsers::OutputFixingParser.from_llm(
          llm: client,
          parser: parser,
        )
        fixed_json = fix_parser.parse(answer)

        # Convert the answer to an array of Issue objects
        sub_issues = []
        if fixed_json && fixed_json["sub_issues"]
          fixed_json["sub_issues"].each do |sub_issue_data|
            sub_issue = Issue.new(sub_issue_data)
            sub_issue.author = User.current
            sub_issues << sub_issue
          end
        end

        ai_helper_logger.debug "Generated sub-issues: #{sub_issues.inspect}"
        sub_issues
      end

      # Find similar issues using VectorTools
      # @param issue [Issue] The issue to find similar issues for
      # @return [Array<Hash>] Array of similar issues with formatted metadata
      def find_similar_issues(issue:)
        return [] unless issue.visible?
        return [] unless AiHelperSetting.vector_search_enabled?

        begin
          vector_tools = RedmineAiHelper::Tools::VectorTools.new
          similar_issues = vector_tools.find_similar_issues(issue_id: issue.id, k: 10)
          
          ai_helper_logger.debug "Found #{similar_issues.length} similar issues for issue #{issue.id}"
          similar_issues
        rescue => e
          ai_helper_logger.error "Similar issues search error: #{e.message}"
          ai_helper_logger.error e.backtrace.join("\n")
          raise e
        end
      end

      # Generate text completion for inline auto-completion
      # @param text [String] The current text content
      # @param cursor_position [Integer] The cursor position in the text
      # @param context [Hash] Context information
      # @return [String] The completion suggestion
      def generate_text_completion(text:, cursor_position: nil, context: {})
        begin
          # Use direct LLM call for simple text completion without tools
          # This is faster and more suitable for inline completion
          
          # Build completion prompt from context
          issue_context = ""
          if context[:issue_title]
            issue_context = "Issue: #{context[:issue_title]}\n"
          end
          
          project_context = ""
          if context[:project_name]
            project_context = "Project: #{context[:project_name]}\n"
          end
          
          prefix_text = cursor_position ? text[0...cursor_position] : text
          suffix_text = (cursor_position && cursor_position < text.length) ? text[cursor_position..-1] : ""
          
          # Simple, focused prompt for completion
          completion_prompt = <<~PROMPT
            #{project_context}#{issue_context}
            Complete the following issue description text starting from the cursor position.
            Provide only the continuation text (1-3 sentences maximum).
            
            Text before cursor: "#{prefix_text}"
            Text after cursor: "#{suffix_text}"
            
            Generate a brief, natural continuation:
          PROMPT
          
          message = { role: "user", content: completion_prompt }
          messages = [message]
          
          # Use the base chat method without streaming for fast response
          completion = chat(messages, {})
          
          ai_helper_logger.debug "Generated text completion: #{completion.length} characters"
          completion
        rescue => e
          ai_helper_logger.error "Text completion error in IssueAgent: #{e.message}"
          ai_helper_logger.error e.backtrace.join("\n")
          # Return empty string on error
          ""
        end
      end

      private

      # Generate a available issue properties string
      def issue_properties
        return "" unless @project
        provider = RedmineAiHelper::Tools::IssueTools.new
        properties = provider.capable_issue_properties(project_id: @project.id)
        content = <<~EOS

          ----

          The following issue properties are available for Project ID: #{@project.id}.

          ```json
          #{JSON.pretty_generate(properties)}
          ```
        EOS
        content
      end
    end
  end
end
