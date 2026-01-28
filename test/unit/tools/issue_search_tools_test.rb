require File.expand_path("../../../test_helper", __FILE__)

class IssueSearchToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields

  def setup
    @provider = RedmineAiHelper::Tools::IssueSearchTools.new
  end

  context "search_issues" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user
    end

    teardown do
      User.current = @previous_user
    end

    should "return issues matching search conditions" do
      result = @provider.search_issues(project_id: @project.id, fields: [
        { field_name: "tracker_id", operator: "=", values: [@tracker.id.to_s] }
      ])

      assert result.key?(:issues)
      assert result.key?(:total_count)
      assert_kind_of Array, result[:issues]
      assert_kind_of Integer, result[:total_count]
    end

    should "return issues when no filters specified" do
      result = @provider.search_issues(project_id: @project.id)

      assert result.key?(:issues)
      assert result.key?(:total_count)
      assert_kind_of Array, result[:issues]
    end

    should "limit results to 50 issues" do
      # Create more than 50 issues
      55.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(project_id: @project.id)

      assert result[:issues].length <= 50
      assert result[:total_count] >= 55
    end

    should "only return issues visible to current user" do
      # Create a private project with a new tracker
      private_tracker = Tracker.create!(name: "PrivateTracker#{Time.now.to_i}#{rand(10000)}", default_status: IssueStatus.first)
      private_project = Project.create!(
        name: "Private Test",
        identifier: "private-test-#{Time.now.to_i}-#{rand(10000)}",
        is_public: false
      )
      # Use save to avoid unique constraint error
      unless private_project.trackers.include?(private_tracker)
        private_project.trackers << private_tracker
      end

      Issue.create!(
        project: private_project,
        tracker: private_tracker,
        subject: "Private Issue",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      # Switch to anonymous user
      User.current = User.anonymous
      result = @provider.search_issues(project_id: private_project.id)

      assert_equal 0, result[:issues].length
      assert_equal 0, result[:total_count]
    ensure
      private_project&.destroy
      private_tracker&.destroy
    end

    should "return formatted issue data with id and name" do
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        subject: "Formatted Test Issue",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      issue_data = result[:issues].find { |i| i[:id] == issue.id }

      assert_not_nil issue_data
      assert_equal "Formatted Test Issue", issue_data[:subject]
      # status should have id and name
      assert_equal issue.status.id, issue_data[:status][:id]
      assert_equal issue.status.name, issue_data[:status][:name]
      # priority should have id and name
      assert_equal issue.priority.id, issue_data[:priority][:id]
      assert_equal issue.priority.name, issue_data[:priority][:name]
      # tracker should have id and name
      assert_equal issue.tracker.id, issue_data[:tracker][:id]
      assert_equal issue.tracker.name, issue_data[:tracker][:name]
      # author should have id and name
      assert_equal issue.author.id, issue_data[:author][:id]
      assert_equal issue.author.name, issue_data[:author][:name]
    ensure
      issue&.destroy
    end

    should "filter issues by tracker condition" do
      # Get issues with specific tracker
      result = @provider.search_issues(
        project_id: @project.id,
        fields: [{ field_name: "tracker_id", operator: "=", values: [@tracker.id.to_s] }]
      )

      # Verify all returned issues have the specified tracker
      assert result[:issues].length > 0, "Should return at least one issue"
      assert result[:issues].all? { |i| i[:tracker][:id] == @tracker.id },
             "All returned issues should have tracker_id #{@tracker.id}"
    end

    should "respect custom limit parameter" do
      # Create 10 issues
      10.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Limit Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(project_id: @project.id, limit: 5)

      assert result[:issues].length <= 5
      assert result[:total_count] >= 10
    end

    should "respect custom limit parameter with filters" do
      # Create 10 issues
      10.times do |i|
        Issue.create!(
          project: @project,
          tracker: @tracker,
          subject: "Limit Filter Test Issue #{i}",
          author: @user,
          status: IssueStatus.first,
          priority: IssuePriority.first
        )
      end

      result = @provider.search_issues(
        project_id: @project.id,
        limit: 3,
        fields: [{ field_name: "tracker_id", operator: "=", values: [@tracker.id.to_s] }]
      )

      assert result[:issues].length <= 3
      assert result[:total_count] >= 10
    end

    should "return custom fields in correct format" do
      # Find a project with custom fields enabled
      issue = Issue.create!(
        project: @project,
        tracker: @tracker,
        subject: "Issue with custom fields",
        author: @user,
        status: IssueStatus.first,
        priority: IssuePriority.first
      )

      result = @provider.search_issues(project_id: @project.id)
      issue_data = result[:issues].find { |i| i[:id] == issue.id }

      assert_not_nil issue_data
      assert_kind_of Array, issue_data[:custom_fields]
    ensure
      issue&.destroy
    end
  end
end
