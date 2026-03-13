require File.expand_path("../../../test_helper", __FILE__)

class IssueUpdateToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields

  def setup
    @provider = RedmineAiHelper::Tools::IssueUpdateTools.new
    User.current = User.find(1)
  end

  context "IssueUpdateTools" do
    context "create_new_issue" do
      should "create issue" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")
        assert response[:id].present?
      end

      should "return error with invalid project" do
        assert_raises(RuntimeError, "Project not found. id = 999") do
          @provider.create_new_issue(project_id: 999, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")
        end
      end

      should "return error with invalid tracker" do
        assert_raises(RuntimeError, "Tracker not found. id = 999") do
          @provider.create_new_issue(project_id: 1, tracker_id: 999, status_id: 1, subject: "test issue", description: "test description")
        end
      end

      should "return error with invalid subject" do
        assert_raises(RuntimeError, "Subject can't be blank") do
          @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "", description: "test description")
        end
      end

      should "create issue with custom fields" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description", custom_fields: [{ field_id: 1, value: "MySQL" }])
        assert response[:id].present?
      end

      should "create issue when custom_fields contains nil field_id" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test nil field_id", custom_fields: [{ field_id: nil, value: "x" }])
        assert response[:id].present?
      end

      should "create issue with mixed nil and valid field_ids, processing only valid ones" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test mixed field_ids", custom_fields: [{ field_id: nil, value: "skip me" }, { field_id: 1, value: "MySQL" }])
        assert response[:id].present?
        issue = Issue.find(response[:id])
        assert_equal "MySQL", issue.custom_field_values.find { |cfv| cfv.custom_field_id == 1 }.value
      end

      should "log warn when custom_fields contains nil field_id" do
        logger = mock("logger")
        logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(logger)
        @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test warn log", custom_fields: [{ field_id: nil, value: "x" }])
      end

      should "create issue when custom_fields contains nonexistent field_id" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test nonexistent field_id", custom_fields: [{ field_id: 99999, value: "x" }])
        assert response[:id].present?
      end

      should "create issue when optional id fields are nil" do
        response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test nil optional ids", priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil)
        assert response[:id].present?
      end

      context "validate_only is true" do
        should "validate issue" do
          response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description", validate_only: true)
          assert response[:issue_id].nil?
        end

        should "return error with invalid project" do
          assert_raises(RuntimeError, "Validation failed") do
            @provider.create_new_issue(project_id: 999, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description", validate_only: true)
          end
        end
      end
    end

    context "update_issue" do
      should "update issue" do
        issue = Issue.find(1)
        @provider.update_issue(issue_id: 1, subject: "test issue")
        assert_equal "test issue", Issue.find(issue.id).subject
      end

      should "return error with invalid id" do
        assert_raises(RuntimeError, "Issue not found. id = 999") do
          @provider.update_issue(issue_id: 999, subject: "test issue")
        end
      end

      should "return error with invalid subject" do
        assert_raises(RuntimeError, "Subject can't be blank") do
          @provider.update_issue(issue_id: 1, subject: "")
        end
      end

      should "update issue with custom fields" do
        @provider.update_issue(issue_id: 1, subject: "test issue", custom_fields: [{ field_id: 1, value: "MySQL" }])
        assert_equal "MySQL", Issue.find(1).custom_field_values.filter { |cfv| cfv.custom_field_id == 1 }.first.value
      end

      should "update issue when custom_fields contains nil field_id" do
        original_subject = Issue.find(1).subject
        @provider.update_issue(issue_id: 1, subject: original_subject, custom_fields: [{ field_id: nil, value: "x" }])
        assert_equal original_subject, Issue.find(1).subject
      end

      should "log warn when update_issue custom_fields contains nil field_id" do
        logger = mock("logger")
        logger.expects(:warn).at_least_once
        @provider.stubs(:ai_helper_logger).returns(logger)
        @provider.update_issue(issue_id: 1, custom_fields: [{ field_id: nil, value: "x" }])
      end

      should "update issue when optional id fields are nil" do
        @provider.update_issue(issue_id: 1, subject: "updated subject", category_id: nil, version_id: nil, assigned_to_id: nil)
        assert_equal "updated subject", Issue.find(1).subject
      end

      should "update issue with comment_to_add" do
        issue = Issue.find(1)
        original_journal_count = issue.journals.size
        @provider.update_issue(issue_id: issue.id, subject: "test issue", comment_to_add: "test comment")
        assert_equal "test issue", Issue.find(1).subject
        assert_equal original_journal_count + 1, Issue.find(1).journals.size
        assert_equal "test comment", Issue.find(1).journals[original_journal_count].notes
      end

      context "validate_only is true" do
        should "validate issue" do
          issue = Issue.find(1)
          original_subject = issue.subject
          @provider.update_issue(issue_id: 1, subject: "test issue", validate_only: true)
          assert_equal original_subject, Issue.find(1).subject
        end

        should "return error with invalid id" do
          assert_raises(RuntimeError, "Validation failed") do
            @provider.update_issue(issue_id: 999, subject: "test issue", validate_only: true)
          end
        end
      end
    end
  end
end
