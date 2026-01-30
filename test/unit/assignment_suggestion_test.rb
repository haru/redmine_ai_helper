require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/assignment_suggestion"

class RedmineAiHelper::AssignmentSuggestionTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users,
           :issue_categories, :versions, :custom_fields, :custom_values,
           :groups_users, :members, :member_roles, :roles, :user_preferences

  context "AssignmentSuggestion" do
    setup do
      @project = projects(:projects_001)
      @user1 = users(:users_002) # John Smith
      @user2 = users(:users_003) # Dave Lopper
      @user3 = users(:users_004) # Robert Hill
      @assignable_users = [@user1, @user2, @user3]
      @suggestion = RedmineAiHelper::AssignmentSuggestion.new(
        project: @project,
        assignable_users: @assignable_users
      )
    end

    context "#suggest" do
      should "return a hash with all three suggestion categories" do
        AiHelperSetting.stubs(:vector_search_enabled?).returns(false)
        result = @suggestion.suggest(subject: "Test issue", description: "Some description")
        assert result.key?(:history_based)
        assert result.key?(:workload_based)
        assert result.key?(:instruction_based)
      end
    end

    context "#suggest_from_history" do
      context "when vector search is disabled" do
        setup do
          AiHelperSetting.stubs(:vector_search_enabled?).returns(false)
        end

        should "return available: false" do
          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: nil)
          assert_equal false, result[:available]
          assert_empty result[:suggestions]
        end
      end

      context "when vector search is enabled" do
        setup do
          AiHelperSetting.stubs(:vector_search_enabled?).returns(true)
        end

        should "return suggestions from similar issues" do
          similar_issues = [
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 90.0 },
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 85.0 },
            { assigned_to: { id: @user2.id, name: @user2.name }, similarity_score: 80.0 },
            { assigned_to: { id: @user2.id, name: @user2.name }, similarity_score: 70.0 },
            { assigned_to: { id: @user2.id, name: @user2.name }, similarity_score: 60.0 },
            { assigned_to: { id: @user3.id, name: @user3.name }, similarity_score: 50.0 },
          ]
          RedmineAiHelper::Llm.any_instance.stubs(:find_similar_issues_by_content).returns(similar_issues)

          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: nil)
          assert_equal true, result[:available]
          assert result[:suggestions].length <= 3

          # user1 should be first (highest cumulative score), user2 second, user3 third
          assert_equal @user1.id, result[:suggestions][0][:user_id]
          assert_equal @user2.id, result[:suggestions][1][:user_id]
          assert_equal @user3.id, result[:suggestions][2][:user_id]
        end

        should "use find_similar_issues for existing issues" do
          issue = issues(:issues_001)
          similar_issues = [
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 90.0 },
          ]
          RedmineAiHelper::Llm.any_instance.stubs(:find_similar_issues).returns(similar_issues)

          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: issue)
          assert_equal true, result[:available]
        end

        should "filter out users not in assignable_users" do
          non_assignable_user = users(:users_001) # admin, not in assignable_users
          similar_issues = [
            { assigned_to: { id: non_assignable_user.id, name: non_assignable_user.name }, similarity_score: 90.0 },
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 80.0 },
          ]
          RedmineAiHelper::Llm.any_instance.stubs(:find_similar_issues_by_content).returns(similar_issues)

          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: nil)
          assert_equal true, result[:available]
          # non_assignable_user should be filtered out
          user_ids = result[:suggestions].map { |s| s[:user_id] }
          assert_not_includes user_ids, non_assignable_user.id
          assert_includes user_ids, @user1.id
        end

        should "filter out issues with nil assigned_to" do
          similar_issues = [
            { assigned_to: nil, similarity_score: 95.0 },
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 80.0 },
          ]
          RedmineAiHelper::Llm.any_instance.stubs(:find_similar_issues_by_content).returns(similar_issues)

          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: nil)
          assert_equal true, result[:available]
          user_ids = result[:suggestions].map { |s| s[:user_id] }
          assert_includes user_ids, @user1.id
        end

        should "include score and similar_issue_count in suggestions" do
          similar_issues = [
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 90.0 },
            { assigned_to: { id: @user1.id, name: @user1.name }, similarity_score: 80.0 },
          ]
          RedmineAiHelper::Llm.any_instance.stubs(:find_similar_issues_by_content).returns(similar_issues)

          result = @suggestion.send(:suggest_from_history, subject: "Test", description: "desc", issue: nil)
          suggestion = result[:suggestions].first
          assert suggestion.key?(:score)
          assert suggestion.key?(:similar_issue_count)
          assert_equal 2, suggestion[:similar_issue_count]
          assert_equal @user1.name, suggestion[:user_name]
        end
      end
    end

    context "#suggest_from_workload" do
      should "return suggestions sorted by ascending open issue count" do
        # Clear existing issue assignments in the project for our test users
        Issue.where(project: @project, assigned_to_id: [@user1.id, @user2.id, @user3.id]).update_all(assigned_to_id: nil)

        open_status = IssueStatus.where(is_closed: false).first
        tracker = @project.trackers.first

        # Assign 3 issues to user1, 1 to user2, 0 to user3
        3.times do
          Issue.create!(
            project: @project,
            tracker: tracker,
            subject: "Test workload issue",
            author: users(:users_001),
            assigned_to: @user1,
            status: open_status,
            priority: IssuePriority.first
          )
        end
        Issue.create!(
          project: @project,
          tracker: tracker,
          subject: "Test workload issue",
          author: users(:users_001),
          assigned_to: @user2,
          status: open_status,
          priority: IssuePriority.first
        )

        result = @suggestion.send(:suggest_from_workload)
        assert_equal true, result[:available]
        assert result[:suggestions].length <= 3

        # user3 (0 issues) should come first, then user2 (1 issue), then user1 (3 issues)
        assert_equal @user3.id, result[:suggestions][0][:user_id]
        assert_equal @user2.id, result[:suggestions][1][:user_id]
        assert_equal @user1.id, result[:suggestions][2][:user_id]
      end

      should "include open_issues_count in suggestions" do
        result = @suggestion.send(:suggest_from_workload)
        assert_equal true, result[:available]
        result[:suggestions].each do |s|
          assert s.key?(:open_issues_count)
          assert s.key?(:user_id)
          assert s.key?(:user_name)
        end
      end

      should "only count issues within the project" do
        open_status = IssueStatus.where(is_closed: false).first
        other_project = projects(:projects_002)
        tracker = other_project.trackers.first || @project.trackers.first

        # Assign an issue in another project - should not be counted
        Issue.create!(
          project: other_project,
          tracker: tracker,
          subject: "Other project issue",
          author: users(:users_001),
          assigned_to: @user1,
          status: open_status,
          priority: IssuePriority.first
        )

        result = @suggestion.send(:suggest_from_workload)
        # The count for user1 should not include the other project's issue
        user1_suggestion = result[:suggestions].find { |s| s[:user_id] == @user1.id }
        # Count only issues from @project assigned to user1
        expected_count = Issue.where(project: @project, assigned_to: @user1)
                              .joins(:status)
                              .where(issue_statuses: { is_closed: false })
                              .count
        assert_equal expected_count, user1_suggestion[:open_issues_count]
      end
    end

    context "#suggest_from_instructions" do
      context "when instructions are not set" do
        should "return available: false" do
          result = @suggestion.send(
            :suggest_from_instructions,
            subject: "Test", description: "desc", tracker_id: nil, category_id: nil
          )
          assert_equal false, result[:available]
          assert_empty result[:suggestions]
        end
      end

      context "when instructions are set" do
        setup do
          @project_setting = AiHelperProjectSetting.settings(@project)
          @project_setting.update!(assignment_suggestion_instructions: "Assign bugs to John Smith")
        end

        should "call LLM and return parsed suggestions" do
          llm_response = {
            "suggestions" => [
              { "user_id" => @user1.id, "reason" => "Bug expert" },
              { "user_id" => @user2.id, "reason" => "Available" },
            ]
          }
          RedmineAiHelper::Llm.any_instance.stubs(:suggest_assignees_by_instructions).returns(llm_response)

          result = @suggestion.send(
            :suggest_from_instructions,
            subject: "Fix bug", description: "A bug needs fixing", tracker_id: 1, category_id: nil
          )
          assert_equal true, result[:available]
          assert_equal 2, result[:suggestions].length
          assert_equal @user1.id, result[:suggestions][0][:user_id]
          assert_equal "Bug expert", result[:suggestions][0][:reason]
          assert_equal @user1.name, result[:suggestions][0][:user_name]
        end

        should "filter out users not in assignable_users" do
          non_assignable_user = users(:users_001)
          llm_response = {
            "suggestions" => [
              { "user_id" => non_assignable_user.id, "reason" => "Admin" },
              { "user_id" => @user1.id, "reason" => "Developer" },
            ]
          }
          RedmineAiHelper::Llm.any_instance.stubs(:suggest_assignees_by_instructions).returns(llm_response)

          result = @suggestion.send(
            :suggest_from_instructions,
            subject: "Fix bug", description: "desc", tracker_id: 1, category_id: nil
          )
          user_ids = result[:suggestions].map { |s| s[:user_id] }
          assert_not_includes user_ids, non_assignable_user.id
          assert_includes user_ids, @user1.id
        end
      end
    end
  end
end
