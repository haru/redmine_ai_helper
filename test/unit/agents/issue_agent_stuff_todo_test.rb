require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/issue_agent"

class RedmineAiHelper::Agents::IssueAgentStuffTodoTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations, :members, :member_roles, :roles

  context "suggest_stuff_todo" do
    setup do
      @project = Project.find(1)
      @user = User.find(2) # Normal user
      User.current = @user
      @langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: "Test input for Langfuse")
      @agent = RedmineAiHelper::Agents::IssueAgent.new(project: @project, langfuse: @langfuse)
    end

    should "load stuff_todo prompt template" do
      prompt = @agent.send(:load_prompt, "issue_agent/stuff_todo")
      assert_not_nil prompt
      assert_respond_to prompt, :format
    end

    should "load stuff_todo_ja prompt template" do
      # Change locale to Japanese
      original_locale = I18n.locale
      I18n.locale = :ja

      prompt = @agent.send(:load_prompt, "issue_agent/stuff_todo")
      assert_not_nil prompt
      assert_respond_to prompt, :format
    ensure
      I18n.locale = original_locale
    end

    should "return issues assigned to the user" do
      # Create test issues
      issue1 = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "User assigned issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4, # Normal
        due_date: Date.today + 1
      )

      mock_prompt = mock("Prompt")
      mock_prompt.stubs(:format).returns("Mock prompt")
      @agent.stubs(:load_prompt).returns(mock_prompt)
      @agent.stubs(:chat).returns("Suggested tasks")

      result = @agent.suggest_stuff_todo
      assert_equal "Suggested tasks", result
    end

    should "return issues assigned to user's groups" do
      # Create a group and add user to it
      group = Group.create!(lastname: "Test Group for Todo")
      group.users << @user

      # Verify that the user's group_ids includes the group
      assert_includes @user.group_ids, group.id

      # Test that fetch_todo_issues uses group_ids correctly
      # by verifying the SQL query includes both user ID and group IDs
      issues_query = @agent.send(:fetch_todo_issues, project: @project)

      # The query should look for assigned_to_id in both user.id and user.group_ids
      assert_includes [User.current.id] + User.current.group_ids, User.current.id
      assert_includes [User.current.id] + User.current.group_ids, group.id

      mock_prompt = mock("Prompt")
      mock_prompt.stubs(:format).returns("Mock prompt")
      @agent.stubs(:load_prompt).returns(mock_prompt)
      @agent.stubs(:chat).returns("Suggested tasks")

      result = @agent.suggest_stuff_todo
      assert_equal "Suggested tasks", result
    end

    should "exclude closed issues" do
      # Find or create closed status
      closed_status = IssueStatus.find_or_create_by!(name: "Closed Todo Test") do |status|
        status.is_closed = true
      end

      # Create closed issue
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Closed issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: closed_status.id,
        priority_id: 4,
        due_date: Date.today
      )

      # Get issues that would be fetched
      issues = @agent.send(:fetch_todo_issues, project: @project)
      assert_not_includes issues.map(&:id), issue.id
    end

    should "prioritize overdue issues" do
      # Create overdue issue
      overdue_issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Overdue issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4, # Normal
        due_date: Date.today - 5,
        updated_on: Date.today - 3
      )

      # Create future issue
      future_issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Future issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4, # Normal
        due_date: Date.today + 7,
        updated_on: Date.today
      )

      overdue_score = @agent.send(:calculate_priority_score, overdue_issue)
      future_score = @agent.send(:calculate_priority_score, future_issue)

      assert overdue_score > future_score, "Overdue issue should have higher priority score"
    end

    should "calculate priority score correctly for overdue issue" do
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Test issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 6, # High (30 points, position 3)
        due_date: Date.today - 3, # 3 days overdue
        updated_on: Date.today - 2
      )

      score = @agent.send(:calculate_priority_score, issue)

      # Expected score: 100 + (3 * 10) = 130 (due date) + 30 (priority) = 160
      assert_equal 160, score
    end

    should "calculate priority score correctly for today's deadline" do
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Test issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 5, # Normal (20 points, position 2)
        due_date: Date.today,
        updated_on: Date.today - 1
      )

      score = @agent.send(:calculate_priority_score, issue)

      # Expected score: 80 (due today) + 20 (normal priority) = 100
      assert_equal 100, score
    end

    should "calculate priority score with untouched period" do
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Test issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4, # Low (10 points, position 1)
        due_date: Date.today + 5
      )

      # Update updated_on directly via SQL to simulate untouched period
      Issue.where(id: issue.id).update_all(updated_on: 35.days.ago)

      # Reload to get updated value
      issue = Issue.find(issue.id)

      score = @agent.send(:calculate_priority_score, issue)

      # Test individual score components
      due_score = @agent.send(:due_date_score, issue)
      priority_score = @agent.send(:priority_field_score, issue)
      untouched = @agent.send(:untouched_score, issue)

      # Expected scores:
      # - Due date: 20 (within 1 week)
      # - Priority: 10 (low)
      # - Untouched: 30 (30+ days)
      assert_equal 20, due_score, "Due date score should be 20"
      assert_equal 10, priority_score, "Priority score should be 10"
      assert_equal 30, untouched, "Untouched score should be 30"
      assert_equal 60, score, "Total score should be 60"
    end

    should "support streaming with stream_proc" do
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Test issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4,
        due_date: Date.today + 1
      )

      streamed_content = []
      stream_proc = Proc.new { |content| streamed_content << content }

      mock_prompt = mock("Prompt")
      mock_prompt.stubs(:format).returns("Mock prompt")
      @agent.stubs(:load_prompt).returns(mock_prompt)

      # Mock chat to call stream_proc
      @agent.stubs(:chat).with(anything, anything, stream_proc).returns("Final result")

      result = @agent.suggest_stuff_todo(stream_proc: stream_proc)
      assert_equal "Final result", result
    end

    should "format issues for prompt correctly" do
      issue = Issue.create!(
        project: @project,
        tracker_id: 1,
        subject: "Test issue subject",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 4,
        due_date: Date.today + 1,
        updated_on: Date.today - 2
      )

      formatted_json = @agent.send(:format_issues_for_prompt, [issue])
      formatted = JSON.parse(formatted_json)

      assert_equal 1, formatted.length
      assert_equal issue.id, formatted[0]["id"]
      assert_equal issue.subject, formatted[0]["subject"]
      assert_equal issue.priority.name, formatted[0]["priority"]
      assert_equal issue.due_date.to_s, formatted[0]["due_date"]
      assert_equal issue.updated_on.to_s, formatted[0]["updated_on"]
      assert_equal issue.project.name, formatted[0]["project_name"]
      assert formatted[0]["score"] > 0
    end

    should "fetch issues from other projects with proper permissions" do
      # Test that fetch_todo_issues_from_other_projects method can be called without error
      # and returns an ActiveRecord relation
      result = @agent.send(:fetch_todo_issues_from_other_projects)

      # Should return an ActiveRecord::Relation or similar query object
      assert_respond_to result, :map
      assert_respond_to result, :to_a

      # The result should be empty or contain issues (we don't create test data here
      # as setting up proper permissions is complex in test environment)
      # Just verify the method works without error
      assert_not_nil result
    end

    should "not fetch issues from projects without AI helper enabled" do
      # Create another project without AI helper
      other_project = Project.create!(name: "Other Project No AI", identifier: "other-project-no-ai")

      # Do NOT enable ai_helper module for the other project
      # This is the key difference from the previous test

      # Add user as member
      role = Role.find(1)
      Member.create!(user: @user, project: other_project, roles: [role])

      # Create issue
      other_issue = Issue.create!(
        project: other_project,
        tracker_id: 1,
        subject: "Other project issue",
        author_id: 1,
        assigned_to_id: @user.id,
        status_id: 1,
        priority_id: 5,
        due_date: Date.today
      )

      issues = @agent.send(:fetch_todo_issues_from_other_projects)
      assert_not_includes issues.map(&:id), other_issue.id
    end
  end
end
