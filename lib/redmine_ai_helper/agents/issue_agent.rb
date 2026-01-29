# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # IssueAgent is a specialized agent for handling Redmine issue-related queries.
    class IssueAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Util::IssueJson
      include ROUTE_HELPERS

      # Backstory for the IssueAgent
      def backstory
        if AiHelperSetting.vector_search_enabled?
          search_answer_instruction = I18n.t("ai_helper.prompts.issue_agent.search_answer_instruction_with_vector")
        else
          search_answer_instruction = I18n.t("ai_helper.prompts.issue_agent.search_answer_instruction")
        end
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
        # Convert issue data to JSON string for the prompt
        json_string = safe_json_for_prompt(issue_json)
        prompt_text = prompt.format(issue: json_string)
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
          issue: safe_json_for_prompt(issue_json),
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
          parent_issue: safe_json_for_prompt(issue_json),
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

      # Find similar issues by content (subject and description) using VectorTools
      # This is used for duplicate checking when creating a new issue.
      # @param subject [String] The subject of the issue
      # @param description [String] The description of the issue
      # @return [Array<Hash>] Array of similar issues with formatted metadata
      def find_similar_issues_by_content(subject:, description:)
        unless AiHelperSetting.vector_search_enabled?
          raise("Vector search is not enabled")
        end

        vector_tools = RedmineAiHelper::Tools::VectorTools.new
        similar_issues = vector_tools.find_similar_issues_by_content(
          subject: subject,
          description: description,
          k: 10,
        )

        ai_helper_logger.debug "Found #{similar_issues.length} similar issues by content"
        similar_issues
      end

      # Generate text completion for inline auto-completion
      # @param text [String] The current text content
      # @param cursor_position [Integer] The cursor position in the text
      # @param context [Hash] Context information
      # @return [String] The completion suggestion
      def generate_text_completion(text:, cursor_position: nil, context_type: "description", project: nil, issue: nil, context: nil)
        begin
          # Build context if not provided (for backward compatibility)
          if context.nil?
            context = build_completion_context(text, context_type, project, issue)
          end

          # Use direct LLM call for simple text completion without tools
          # This is faster and more suitable for inline completion

          prefix_text = cursor_position ? text[0...cursor_position] : text
          suffix_text = (cursor_position && cursor_position < text.length) ? text[cursor_position..-1] : ""

          # Determine which template to use based on context type
          actual_context_type = context[:context_type] || context_type || "description"
          template_name = actual_context_type == "note" ? "issue_agent/note_inline_completion" : "issue_agent/inline_completion"

          # Load prompt template using PromptLoader
          prompt = load_prompt(template_name)

          # Prepare template variables
          template_vars = {
            prefix_text: prefix_text,
            suffix_text: suffix_text,
            issue_title: context[:issue_title] || "New Issue",
            project_name: context[:project_name] || "Unknown Project",
            cursor_position: cursor_position.to_s,
            max_sentences: "3",
            format: Setting.text_formatting,
          }

          # Add note-specific variables
          if actual_context_type == "note"
            template_vars.merge!({
              issue_description: context[:issue_description] || "",
              issue_status: context[:issue_status] || "",
              issue_assigned_to: context[:issue_assigned_to] || "None",
              current_user_name: context[:current_user_name] || "",
              user_role: context.dig(:user_role_context, :suggested_role) || "participant",
            })

            # Add recent notes
            if context[:recent_notes]&.any?
              recent_notes_text = context[:recent_notes][0..4].map do |note|
                "#{note[:user_name]} (#{note[:created_on]}): #{note[:notes]}"
              end.join("\n")
              template_vars[:recent_notes] = recent_notes_text
            else
              template_vars[:recent_notes] = "No recent notes available."
            end
          end

          prompt_text = prompt.format(**template_vars)

          message = { role: "user", content: prompt_text }
          messages = [message]

          # Use the base chat method without streaming for fast response
          completion = chat(messages, {})

          ai_helper_logger.debug "Generated text completion: #{completion.length} characters"

          # Parse and clean the response
          parse_completion_response(completion)
        rescue => e
          ai_helper_logger.error "Text completion error in IssueAgent: #{e.message}"
          ai_helper_logger.error "Error backtrace: #{e.backtrace.join("\n")}"
          ""
        end
      end

      private

      # Generate a available issue properties string
      # Build context for completion based on project and issue information
      # Moved from llm.rb to follow agent architecture
      # @param text [String] The input text
      # @param context_type [String] Type of context ('description' or 'note')
      # @param project [Project] The project instance
      # @param issue [Issue] The issue instance
      # @return [Hash] Context information
      def build_completion_context(text, context_type, project, issue)
        context = {
          context_type: context_type,
          project_name: project&.name,
          issue_title: issue&.subject,
          text_length: text.length,
        }

        # Add project-specific context if available
        if project
          context[:project_description] = project.description if project.description.present?
          context[:project_identifier] = project.identifier
        end

        # Add note-specific context
        if context_type == "note" && issue
          context.merge!(build_note_specific_context(issue))
        end

        context
      end

      # Build note-specific context using IssueJson
      # Moved from llm.rb to follow agent architecture
      # @param issue [Issue] The issue instance
      # @return [Hash] Note-specific context information
      def build_note_specific_context(issue)
        # Current user
        current_user = User.current

        # Use IssueJson to get comprehensive issue data (already included in this class)
        issue_data = generate_issue_data(issue)

        # Extract and format data for note completion context
        note_context = {
          issue_id: issue_data[:id],
          issue_subject: issue_data[:subject],
          issue_description: issue_data[:description].present? ? issue_data[:description][0..500] : "", # First 500 characters only
          issue_status: issue_data.dig(:status, :name) || "",
          issue_priority: issue_data.dig(:priority, :name) || "",
          issue_tracker: issue_data.dig(:tracker, :name) || "",
          issue_assigned_to: issue_data.dig(:assigned_to, :name) || "None",
          issue_author: issue_data.dig(:author, :name) || "",
          issue_created_on: issue_data[:created_on],
          current_user_name: current_user.name,
          current_user_id: current_user.id,
        }

        # Extract recent notes from journals (limit to latest 20 with notes)
        journals_with_notes = issue_data[:journals]
          .select { |journal| journal[:notes].present? && !journal[:private_notes] }
          .first(20) # Already sorted by created_on desc in generate_issue_data

        note_context[:recent_notes] = journals_with_notes.map do |journal|
          {
            user_name: journal.dig(:user, :name) || "Unknown",
            user_id: journal.dig(:user, :id),
            notes: journal[:notes][0..300], # First 300 characters only
            created_on: journal[:created_on],
            is_current_user: journal.dig(:user, :id) == current_user.id,
          }
        end

        # User role analysis
        user_roles = analyze_user_role_in_conversation(current_user, journals_with_notes, issue_data)
        note_context[:user_role_context] = user_roles

        note_context
      end

      # Method to analyze user's role in conversation
      # Moved from llm.rb to follow agent architecture
      # @param current_user [User] Current user
      # @param journals [Array] Journal entries
      # @param issue_data [Hash] Issue data
      # @return [Hash] User role analysis
      def analyze_user_role_in_conversation(current_user, journals, issue_data)
        role_info = {
          is_issue_author: issue_data.dig(:author, :id) == current_user.id,
          is_assignee: issue_data.dig(:assigned_to, :id) == current_user.id,
          participation_count: journals.count { |j| j.dig(:user, :id) == current_user.id },
          last_participation_date: journals.find { |j| j.dig(:user, :id) == current_user.id }&.dig(:created_on),
          conversation_participants: journals.map { |j| j.dig(:user, :name) }.uniq.compact,
        }

        # User's role in the conversation flow
        if role_info[:is_issue_author]
          role_info[:suggested_role] = "issue_author"
        elsif role_info[:is_assignee]
          role_info[:suggested_role] = "assignee"
        elsif role_info[:participation_count] > 0
          role_info[:suggested_role] = "participant"
        else
          role_info[:suggested_role] = "new_participant"
        end

        role_info
      end

      # Parse and clean completion response
      # Moved from llm.rb parse_single_suggestion to follow agent architecture
      # @param response [String] Raw LLM response
      # @return [String] Cleaned completion suggestion
      def parse_completion_response(response)
        return "" if response.blank?

        # Remove any unwanted prefixes or suffixes
        suggestion = response.strip

        # Remove any markdown code block markers (multiline)
        suggestion = suggestion.gsub(/```[^\n]*\n.*?\n```/m, "")

        # Remove any potential markdown formatting
        suggestion = suggestion.gsub(/^\*+\s*/, "")  # Remove bullet points
        suggestion = suggestion.gsub(/^#+\s*/, "")   # Remove headers
        suggestion = suggestion.gsub(/\*\*(.*?)\*\*/, '\1')  # Remove bold
        suggestion = suggestion.gsub(/\*(.*?)\*/, '\1')      # Remove italic

        # Normalize multiple spaces to single spaces
        suggestion = suggestion.gsub(/\s+/, " ")

        # Clean up any leading/trailing whitespace after processing
        suggestion = suggestion.strip

        # Limit to reasonable length (max 3 sentences as per spec)
        # Split on sentence-ending punctuation but preserve the punctuation
        sentences = suggestion.split(/(?<=[.!?])\s+/)
        if sentences.length > 3
          suggestion = sentences[0..2].join(" ")
        end

        suggestion
      end

      def issue_properties
        return "" unless @project
        provider = RedmineAiHelper::Tools::IssueTools.new
        properties = provider.capable_issue_properties(project_id: @project.id)
        content = <<~EOS

          ----

          The following issue properties are available for Project ID: #{@project.id}.

          ```json
          #{safe_json_for_prompt(properties)}
          ```
        EOS
        content
      end

      # Generate a JSON string safe for prompt interpolation.
      # Escapes backslashes to prevent them from being consumed by the prompt formatter.
      # @param data [Hash] The data to convert to JSON.
      # @return [String] The safe JSON string.
      def safe_json_for_prompt(data)
        json = JSON.pretty_generate(data)
        # Langchain's prompt format consumes one level of backslash escaping.
        # We need to double-escape backslashes so they survive the formatting.
        json.gsub(/\\/) { "\\\\" }
      end
    end
  end
end
