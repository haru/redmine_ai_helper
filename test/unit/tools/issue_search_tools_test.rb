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
      # Avoid adding the same tracker twice to prevent uniqueness violations on the join table
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

  context "validate_search_params" do
    # T003
    context "when fields is nil" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, nil, [])
        end
      end

      should "return empty errors array" do
        errors = @provider.send(:validate_search_params, nil, [])
        assert_equal [], errors
      end
    end

    # T004
    context "when date_fields is nil" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [], nil)
        end
      end

      should "return empty errors array" do
        errors = @provider.send(:validate_search_params, [], nil)
        assert_equal [], errors
      end
    end

    # T005
    context "when field_name is nil in fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params,
            [{ field_name: nil, operator: "=", values: ["1"] }], [])
        end
      end

      should "add an error message mentioning field_name" do
        errors = @provider.send(:validate_search_params,
          [{ field_name: nil, operator: "=", values: ["1"] }], [])
        assert errors.any? { |e| e.include?("field_name") },
          "Expected error message to mention field_name, got: #{errors.inspect}"
      end
    end

    # T006
    context "when values is nil in fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params,
            [{ field_name: "tracker_id", operator: "=", values: nil }], [])
        end
      end

      should "add an error message mentioning values" do
        errors = @provider.send(:validate_search_params,
          [{ field_name: "tracker_id", operator: "=", values: nil }], [])
        assert errors.any? { |e| e.include?("values") },
          "Expected error message to mention values, got: #{errors.inspect}"
      end
    end

    # T007
    context "when field_name is nil in date_fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [{ field_name: nil, operator: "=", values: ["2024-01-01"] }])
        end
      end

      should "add an error message mentioning field_name" do
        errors = @provider.send(:validate_search_params, [],
          [{ field_name: nil, operator: "=", values: ["2024-01-01"] }])
        assert errors.any? { |e| e.include?("field_name") },
          "Expected error message to mention field_name, got: #{errors.inspect}"
      end
    end

    # T008
    context "when values is nil in date_fields" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [{ field_name: "due_date", operator: "=", values: nil }])
        end
      end

      should "add an error message mentioning values" do
        errors = @provider.send(:validate_search_params, [],
          [{ field_name: "due_date", operator: "=", values: nil }])
        assert errors.any? { |e| e.include?("values") },
          "Expected error message to mention values, got: #{errors.inspect}"
      end
    end

    # T009
    context "when a value element is nil in date_fields values" do
      should "not raise an exception" do
        assert_nothing_raised do
          @provider.send(:validate_search_params, [],
            [{ field_name: "due_date", operator: "=", values: [nil, "2024-01-01"] }])
        end
      end

      should "add an error message for the nil value" do
        errors = @provider.send(:validate_search_params, [],
          [{ field_name: "due_date", operator: "=", values: [nil, "2024-01-01"] }])
        assert errors.any?,
          "Expected at least one error message, got empty array"
      end
    end

    # T010
    context "when nil and valid fields are mixed" do
      should "continue validating valid fields after encountering a nil field_name" do
        errors = @provider.send(:validate_search_params, [
          { field_name: nil, operator: "=", values: ["1"] },
          { field_name: "tracker_id", operator: "=", values: ["not-a-number"] }
        ], [])
        # Expect error from nil field_name AND error from invalid numeric value
        assert errors.length >= 2,
          "Expected at least 2 errors (nil field_name + invalid numeric), got: #{errors.inspect}"
      end

      should "continue validating date_fields after encountering a nil field" do
        errors = @provider.send(:validate_search_params, [],
          [
            { field_name: nil, operator: "=", values: ["2024-01-01"] },
            { field_name: "due_date", operator: "=", values: ["not-a-date"] }
          ])
        assert errors.length >= 2,
          "Expected at least 2 errors, got: #{errors.inspect}"
      end
    end

    # T014 / T015 - warn logging
    context "warn logging when field_name is nil" do
      should "call ai_helper_logger warn when field_name is nil in fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params,
          [{ field_name: nil, operator: "=", values: ["1"] }], [])
      end
    end

    context "warn logging when values is nil" do
      should "call ai_helper_logger warn when values is nil in fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params,
          [{ field_name: "tracker_id", operator: "=", values: nil }], [])
      end

      should "call ai_helper_logger warn when values is nil in date_fields" do
        mock_logger = mock("logger")
        mock_logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(mock_logger)
        @provider.send(:validate_search_params, [],
          [{ field_name: "due_date", operator: "=", values: nil }])
      end
    end
  end
end
