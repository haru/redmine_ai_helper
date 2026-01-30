module RedmineAiHelper
  # Service class for suggesting issue assignees based on multiple strategies
  class AssignmentSuggestion
    include RedmineAiHelper::Logger

    MAX_SUGGESTIONS = 3

    # @param project [Project] The project context
    # @param assignable_users [Array<User>] Users who can be assigned to issues
    def initialize(project:, assignable_users:)
      @project = project
      @assignable_users = assignable_users
      @assignable_user_ids = assignable_users.map(&:id).to_set
    end

    # Run all suggestion strategies and return combined results
    # @param subject [String] Issue subject
    # @param description [String] Issue description
    # @param tracker_id [Integer, nil] Tracker ID
    # @param category_id [Integer, nil] Category ID
    # @param issue [Issue, nil] Existing issue (nil for new issues)
    # @return [Hash] Combined results from all strategies
    def suggest(subject:, description:, tracker_id: nil, category_id: nil, issue: nil)
      {
        history_based: suggest_from_history(subject: subject, description: description, issue: issue),
        workload_based: suggest_from_workload,
        instruction_based: suggest_from_instructions(
          subject: subject, description: description,
          tracker_id: tracker_id, category_id: category_id
        ),
      }
    end

    private

    # Suggest assignees based on similar issue history using vector search
    def suggest_from_history(subject:, description:, issue:)
      unless AiHelperSetting.vector_search_enabled?
        return { available: false, suggestions: [] }
      end

      begin
        llm = RedmineAiHelper::Llm.new
        similar_issues = if issue
                           llm.find_similar_issues(issue: issue)
                         else
                           llm.find_similar_issues_by_content(
                             subject: subject, description: description, project: @project
                           )
                         end

        aggregate_history_suggestions(similar_issues)
      rescue => e
        ai_helper_logger.error "History-based suggestion error: #{e.message}"
        { available: true, suggestions: [] }
      end
    end

    # Suggest assignees based on current workload (fewest open issues)
    def suggest_from_workload
      open_issue_counts = Issue.where(project: @project, assigned_to_id: @assignable_user_ids)
                               .joins(:status)
                               .where(issue_statuses: { is_closed: false })
                               .group(:assigned_to_id)
                               .count

      suggestions = @assignable_users.map do |user|
        {
          user_id: user.id,
          user_name: user.name,
          open_issues_count: open_issue_counts[user.id] || 0,
        }
      end

      suggestions.sort_by! { |s| s[:open_issues_count] }
      suggestions = suggestions.first(MAX_SUGGESTIONS)

      { available: true, suggestions: suggestions }
    end

    # Suggest assignees based on user-defined instructions via LLM
    def suggest_from_instructions(subject:, description:, tracker_id:, category_id:)
      project_setting = AiHelperProjectSetting.settings(@project)
      instructions = project_setting.assignment_suggestion_instructions

      if instructions.blank?
        return { available: false, suggestions: [] }
      end

      begin
        llm = RedmineAiHelper::Llm.new
        llm_response = llm.suggest_assignees_by_instructions(
          project: @project,
          assignable_users: @assignable_users,
          instructions: instructions,
          subject: subject,
          description: description,
          tracker_id: tracker_id,
          category_id: category_id,
        )

        parse_instruction_suggestions(llm_response)
      rescue => e
        ai_helper_logger.error "Instruction-based suggestion error: #{e.message}"
        { available: true, suggestions: [] }
      end
    end

    # Aggregate similar issues by assigned_to, scoring by similarity
    def aggregate_history_suggestions(similar_issues)
      user_scores = {}

      similar_issues.each do |issue_data|
        assigned_to = issue_data[:assigned_to] || issue_data["assigned_to"]
        next unless assigned_to

        user_id = assigned_to[:id] || assigned_to["id"]
        user_name = assigned_to[:name] || assigned_to["name"]
        score = issue_data[:similarity_score] || issue_data["similarity_score"] || 0

        next unless @assignable_user_ids.include?(user_id)

        user_scores[user_id] ||= { user_name: user_name, total_score: 0, count: 0 }
        user_scores[user_id][:total_score] += score
        user_scores[user_id][:count] += 1
      end

      suggestions = user_scores.map do |user_id, data|
        {
          user_id: user_id,
          user_name: data[:user_name],
          score: (data[:total_score] / data[:count]).round(1),
          similar_issue_count: data[:count],
        }
      end

      suggestions.sort_by! { |s| -s[:score] }
      suggestions = suggestions.first(MAX_SUGGESTIONS)

      { available: true, suggestions: suggestions }
    end

    # Parse LLM instruction-based response and filter by assignable users
    def parse_instruction_suggestions(llm_response)
      raw_suggestions = llm_response["suggestions"] || []
      user_map = @assignable_users.index_by(&:id)

      suggestions = raw_suggestions.filter_map do |s|
        user_id = s["user_id"]
        user = user_map[user_id]
        next unless user

        {
          user_id: user_id,
          user_name: user.name,
          reason: s["reason"],
        }
      end

      suggestions = suggestions.first(MAX_SUGGESTIONS)
      { available: true, suggestions: suggestions }
    end
  end
end
