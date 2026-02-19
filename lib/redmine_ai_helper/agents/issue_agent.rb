# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # IssueAgent is a specialized agent for handling Redmine issue-related queries.
    class IssueAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Util::IssueJson
      include RedmineAiHelper::Util::AttachmentFileHelper
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

      # Returns the list of available RubyLLM::Tool subclasses for the IssueAgent.
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_providers
        providers = []
        if AiHelperSetting.vector_search_enabled?
          providers << RedmineAiHelper::Tools::VectorTools
        end
        providers << RedmineAiHelper::Tools::IssueTools
        providers << RedmineAiHelper::Tools::ProjectTools
        providers << RedmineAiHelper::Tools::UserTools
        providers << RedmineAiHelper::Tools::IssueSearchTools
        providers << RedmineAiHelper::Tools::FileTools
        providers
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
        json_string = JSON.pretty_generate(issue_json)
        prompt_text = prompt.format(issue: json_string)
        message = { role: "user", content: prompt_text }
        messages = [message]

        file_paths = supported_attachment_paths(issue)
        chat(messages, {}, stream_proc, with: file_paths.presence)
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

        file_paths = supported_attachment_paths(issue)
        chat(messages, {}, stream_proc, with: file_paths.presence)
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
        issue_json = generate_issue_data(issue)
        project_setting = AiHelperProjectSetting.settings(issue.project)

        prompt_text = prompt.format(
          parent_issue: JSON.pretty_generate(issue_json),
          instructions: instructions,
          subtask_instructions: project_setting.subtask_instructions,
          format_instructions: RedmineAiHelper::Util::StructuredOutputHelper.get_format_instructions(json_schema),
        )
        ai_helper_logger.debug "prompt_text: #{prompt_text}"

        message = { role: "user", content: prompt_text }
        messages = [message]
        file_paths = supported_attachment_paths(issue)
        answer = chat(messages, {}, nil, with: file_paths.presence)
        fixed_json = RedmineAiHelper::Util::StructuredOutputHelper.parse(
          response: answer,
          json_schema: json_schema,
          chat_method: method(:chat),
          messages: messages,
        )

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

      # Suggest assignees based on user instructions using structured LLM output
      # @param assignable_users [Array<User>] Users who can be assigned
      # @param instructions [String] User-defined instructions
      # @param subject [String] Issue subject
      # @param description [String] Issue description
      # @param tracker_id [Integer, nil] Tracker ID
      # @param category_id [Integer, nil] Category ID
      # @return [Hash] Parsed JSON response with suggestions
      def suggest_assignees_by_instructions(assignable_users:, instructions:, subject:, description:, tracker_id: nil, category_id: nil)
        json_schema = {
          type: "object",
          properties: {
            suggestions: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  user_id: { type: "integer" },
                  reason: { type: "string" },
                },
                required: ["user_id", "reason"],
              },
            },
          },
          required: ["suggestions"],
        }
        users_text = assignable_users.map { |u| "- #{u.name} (ID: #{u.id})" }.join("\n")
        tracker_name = tracker_id ? Tracker.find_by(id: tracker_id)&.name : ""
        category_name = category_id ? IssueCategory.find_by(id: category_id)&.name : ""

        prompt = load_prompt("assignment_suggestion_prompt")
        prompt_text = prompt.format(
          instructions: instructions,
          assignable_users: users_text,
          subject: subject || "",
          description: description || "",
          tracker: tracker_name || "",
          category: category_name || "",
          format_instructions: RedmineAiHelper::Util::StructuredOutputHelper.get_format_instructions(json_schema),
        )

        message = { role: "user", content: prompt_text }
        messages = [message]
        answer = chat(messages)

        RedmineAiHelper::Util::StructuredOutputHelper.parse(
          response: answer,
          json_schema: json_schema,
          chat_method: method(:chat),
          messages: messages,
        )
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

      # Suggest stuff to do today with streaming support
      # @param stream_proc [Proc] Optional callback proc for streaming content
      # @return [String] Markdown-formatted suggestions
      def suggest_stuff_todo(stream_proc: nil)
        # Get issues from current project
        current_project_issues = fetch_todo_issues(project: @project)

        # Get issues from other projects with proper permissions
        other_project_issues = fetch_todo_issues_from_other_projects

        # Prioritize and limit issues
        current_prioritized = prioritize_issues(current_project_issues).take(5)
        other_prioritized = prioritize_issues(other_project_issues).take(5)

        # Load prompt template
        prompt = load_prompt("issue_agent/stuff_todo")

        # Format issues for prompt
        current_issues_text = format_issues_for_prompt(current_prioritized)
        other_issues_text = format_issues_for_prompt(other_prioritized)

        # Build prompt
        prompt_text = prompt.format(
          current_project_issues: current_issues_text,
          other_project_issues: other_issues_text,
          current_project_name: @project.name
        )

        message = { role: "user", content: prompt_text }
        messages = [message]

        # Call LLM with streaming support
        chat(messages, {}, stream_proc)
      end

      private

      # Fetch todo issues based on options
      # @param options [Hash] Options for filtering issues
      # @option options [Project] :project The project to fetch issues from
      # @option options [Array<Project>] :projects The projects to fetch issues from
      # @return [ActiveRecord::Relation] Issues matching the criteria
      def fetch_todo_issues(options = {})
        project = options[:project] || @project
        projects = options[:projects] || [project]

        # Get current user's group IDs
        group_ids = User.current.group_ids

        Issue.visible
          .where(project: projects)
          .where(assigned_to_id: [User.current.id] + group_ids)
          .joins(:status)
          .where.not(issue_statuses: { is_closed: true })
      end

      # Fetch issues from other projects with proper permissions
      # @return [ActiveRecord::Relation] Issues from other projects
      def fetch_todo_issues_from_other_projects
        # Get all visible projects except current project
        eligible_projects = Project.visible
          .where.not(id: @project.id)
          .select do |proj|
            proj.module_enabled?(:ai_helper) &&
              User.current.allowed_to?(:view_ai_helper, proj)
          end

        return Issue.none if eligible_projects.empty?

        fetch_todo_issues(projects: eligible_projects)
      end

      # Prioritize issues by calculated score
      # @param issues [ActiveRecord::Relation] Issues to prioritize
      # @return [Array<Issue>] Sorted issues by priority score (descending)
      def prioritize_issues(issues)
        issues.sort_by { |issue| -calculate_priority_score(issue) }
      end

      # Calculate priority score for an issue
      # @param issue [Issue] The issue to calculate score for
      # @return [Integer] The calculated priority score
      def calculate_priority_score(issue)
        score = 0
        score += due_date_score(issue)
        score += priority_field_score(issue)
        score += untouched_score(issue)
        score
      end

      # Calculate score based on due date
      # @param issue [Issue] The issue
      # @return [Integer] The due date score
      def due_date_score(issue)
        return 0 unless issue.due_date

        days_until_due = (issue.due_date - Date.today).to_i

        if days_until_due < 0
          # Overdue: 100 + (days overdue * 10), max 150
          [100 + (days_until_due.abs * 10), 150].min
        elsif days_until_due == 0
          # Due today
          80
        elsif days_until_due == 1
          # Due tomorrow
          60
        elsif days_until_due <= 3
          # Due within 3 days
          40
        elsif days_until_due <= 7
          # Due within 1 week
          20
        else
          # Due date is more than 1 week away
          0
        end
      end

      # Calculate score based on priority field
      # @param issue [Issue] The issue
      # @return [Integer] The priority field score
      def priority_field_score(issue)
        return 20 unless issue.priority

        # Map priority names to scores
        # Redmine default priorities: Low(1), Normal(2), High(3), Urgent(4), Immediate(5)
        case issue.priority.position
        when 5
          50 # Immediate
        when 4
          40 # Urgent
        when 3
          30 # High
        when 2
          20 # Normal
        when 1
          10 # Low
        else
          20 # Default to Normal
        end
      end

      # Calculate score based on untouched period
      # @param issue [Issue] The issue
      # @return [Integer] The untouched period score
      def untouched_score(issue)
        return 0 unless issue.updated_on

        days_untouched = (Date.today - issue.updated_on.to_date).to_i

        if days_untouched >= 30
          30
        elsif days_untouched >= 14
          20
        elsif days_untouched >= 7
          10
        else
          0
        end
      end

      # Format issues for prompt
      # @param issues [Array<Issue>] Issues to format
      # @return [String] Formatted issues text
      def format_issues_for_prompt(issues)
        return "No issues" if issues.empty?

        issues.map do |issue|
          {
            id: issue.id,
            subject: issue.subject,
            priority: issue.priority&.name || "Normal",
            due_date: issue.due_date&.to_s || "None",
            updated_on: issue.updated_on.to_s,
            project_name: issue.project.name,
            score: calculate_priority_score(issue)
          }
        end.to_json
      end

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
          #{JSON.pretty_generate(properties)}
          ```
        EOS
        content
      end

    end
  end
end
