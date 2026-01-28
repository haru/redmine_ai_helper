require File.expand_path("../../../test_helper", __FILE__)

class IssueSearchToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields

  def setup
    @provider = RedmineAiHelper::Tools::IssueSearchTools.new
  end

  context "generate_url" do
    should "generate url with filters" do
      project = Project.find(1)
      response = @provider.generate_url(project_id: 1, fields: [{ field_name: "tracker_id", operator: "=", values: ["1"] }])
      assert_match "/projects/#{project.identifier}/issues?set_filter=1", response[:url]
    end

    should "generate url with no filters" do
      project = Project.find(1)
      response = @provider.generate_url(project_id: 1)
      assert_equal "/projects/#{project.identifier}/issues", response[:url]
    end

    should "generate url with date fields" do
      response = @provider.generate_url(project_id: 1, date_fields: [{ field_name: "created_on", operator: ">=", values: ["2020-01-01"] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=created_on")
      assert url_value.include?("op[created_on]=>")
      assert url_value.include?("v[created_on][]=2020-01-01")
    end

    should "generate url with time fields" do
      response = @provider.generate_url(project_id: 1, time_fields: [{ field_name: "estimated_hours", operator: "=", values: ["6"] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=estimated_hours")
      assert url_value.include?("op[estimated_hours]==")
      assert url_value.include?("v[estimated_hours][]=6")
    end

    should "generate url with number fields" do
      response = @provider.generate_url(project_id: 1, number_fields: [{ field_name: "done_ratio", operator: "=", values: ["6"] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=done_ratio")
      assert url_value.include?("op[done_ratio]==")
      assert url_value.include?("v[done_ratio][]=6")
    end

    should "generate url with text fields" do
      response = @provider.generate_url(project_id: 1, text_fields: [{ field_name: "subject", operator: "~", value: ["test"] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=subject")
      assert url_value.include?("op[subject]=~")
      # TODO: Fix this test
      # assert url_value.include?("v[subject][]=test")
    end

    should "generate url with status fields" do
      response = @provider.generate_url(project_id: 1, status_field: [{ field_name: "status_id", operator: "=", values: [1] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=status_id")
      assert url_value.include?("op[status_id]==")
      assert url_value.include?("v[status_id][]=1")
    end

    should "generate url with custom field" do
      response = @provider.generate_url(project_id: 1, custom_fields: [{ field_id: 1, operator: "=", values: ["MySQL"] }])
      url_value = CGI.unescape(response[:url])
      assert url_value.include?("f[]=cf_1")
      assert url_value.include?("op[cf_1]==")
      assert url_value.include?("v[cf_1][]=MySQL")
    end
  end

  context "search_issues" do
    setup do
      @project = Project.find(1)
      @tracker = Tracker.find(1)
      @user = User.find(2)
      User.current = @user
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
