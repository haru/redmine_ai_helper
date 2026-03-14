require File.expand_path("../../../test_helper", __FILE__)

class IssueUpdateToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :issue_relations

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

      context "parent_issue_id" do
        should "set parent when valid parent_issue_id is provided" do
          parent = Issue.find(1)
          response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "child issue", parent_issue_id: parent.id)
          created_issue = Issue.find(response[:id])
          assert_equal parent.id, created_issue.parent_id
        end

        should "raise error when parent_issue_id does not exist" do
          assert_raises(RuntimeError) do
            @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "child issue", parent_issue_id: 99999)
          end
        end

        should "skip parent assignment when parent_issue_id is nil" do
          response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "no parent issue", parent_issue_id: nil)
          assert response[:id].present?
          issue = Issue.find(response[:id])
          assert_nil issue.parent_issue_id
        end

        should "validate parent_issue_id existence when validate_only is true without saving" do
          parent = Issue.find(1)
          count_before = Issue.count
          @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "validate only child", parent_issue_id: parent.id, validate_only: true)
          assert_equal count_before, Issue.count
        end

        should "raise error for non-existent parent_issue_id when validate_only is true" do
          assert_raises(RuntimeError) do
            @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "validate parent", parent_issue_id: 99999, validate_only: true)
          end
        end
      end

      context "relations" do
        should "create relation when valid relations are provided" do
          target = Issue.find(3)
          response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "issue with relation", relations: [{ issue_id: target.id, relation_type: "relates" }])
          created_issue = Issue.find(response[:id])
          assert created_issue.relations.any? { |r| r.issue_from_id == created_issue.id && r.issue_to_id == target.id || r.issue_from_id == target.id && r.issue_to_id == created_issue.id }
        end

        should "raise error when relation_type is invalid" do
          assert_raises(RuntimeError) do
            @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "bad relation type", relations: [{ issue_id: 1, relation_type: "invalid_type" }])
          end
        end

        should "skip and log warning when relations entry has nil issue_id" do
          logger = mock("logger")
          logger.stubs(:warn)
          @provider.stubs(:ai_helper_logger).returns(logger)
          logger.expects(:warn).with(regexp_matches(/issue_id/)).at_least_once
          response = @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "nil issue_id relation", relations: [{ issue_id: nil, relation_type: "relates" }])
          assert response[:id].present?
        end

        should "validate relation existence when validate_only is true without saving" do
          target = Issue.find(3)
          count_before = Issue.count
          @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "validate relations", relations: [{ issue_id: target.id, relation_type: "relates" }], validate_only: true)
          assert_equal count_before, Issue.count
        end

        should "raise error for non-existent issue_id in relations when validate_only is true" do
          assert_raises(RuntimeError) do
            @provider.create_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "validate bad relation", relations: [{ issue_id: 99999, relation_type: "relates" }], validate_only: true)
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

      context "parent_issue_id" do
        should "set parent when valid parent_issue_id is provided" do
          parent = Issue.find(1)
          child = Issue.find(2)
          @provider.update_issue(issue_id: child.id, parent_issue_id: parent.id)
          assert_equal parent.id, Issue.find(child.id).parent_id
        end

        should "clear parent when parent_issue_id is 0" do
          parent = Issue.find(1)
          child = Issue.find(2)
          child.parent_issue_id = parent.id
          child.save!
          @provider.update_issue(issue_id: child.id, parent_issue_id: 0)
          assert_nil Issue.find(child.id).parent_id
        end

        should "raise error when parent_issue_id does not exist" do
          assert_raises(RuntimeError) do
            @provider.update_issue(issue_id: 1, parent_issue_id: 99999)
          end
        end

        should "skip when parent_issue_id is nil leaving existing parent unchanged" do
          parent = Issue.find(1)
          child = Issue.find(2)
          child.parent_issue_id = parent.id
          child.save!
          @provider.update_issue(issue_id: child.id, parent_issue_id: nil)
          assert_equal parent.id, Issue.find(child.id).parent_id
        end
      end

      context "relations_to_add" do
        should "add a new relation when valid relations_to_add is provided" do
          issue = Issue.find(1)
          target = Issue.find(3)
          @provider.update_issue(issue_id: issue.id, relations_to_add: [{ issue_id: target.id, relation_type: "relates" }])
          issue.reload
          assert issue.relations.any? { |r| r.issue_from_id == target.id || r.issue_to_id == target.id }
        end

        should "be idempotent when adding a relation that already exists" do
          issue = Issue.find(1)
          target = Issue.find(3)
          IssueRelation.create!(issue_from_id: issue.id, issue_to_id: target.id, relation_type: "relates")
          assert_nothing_raised do
            @provider.update_issue(issue_id: issue.id, relations_to_add: [{ issue_id: target.id, relation_type: "relates" }])
          end
        end

        should "validate relation existence when validate_only is true without saving" do
          target = Issue.find(3)
          original_subject = Issue.find(1).subject
          @provider.update_issue(issue_id: 1, relations_to_add: [{ issue_id: target.id, relation_type: "relates" }], validate_only: true)
          assert_equal original_subject, Issue.find(1).subject
        end

        should "raise error for non-existent issue_id in relations_to_add when validate_only is true" do
          assert_raises(RuntimeError) do
            @provider.update_issue(issue_id: 1, relations_to_add: [{ issue_id: 99999, relation_type: "relates" }], validate_only: true)
          end
        end
      end

      context "relations_to_remove" do
        should "remove an existing relation when relations_to_remove is provided" do
          issue = Issue.find(1)
          target = Issue.find(3)
          IssueRelation.create!(issue_from_id: issue.id, issue_to_id: target.id, relation_type: "relates")
          @provider.update_issue(issue_id: issue.id, relations_to_remove: [{ issue_id: target.id }])
          issue.reload
          assert issue.relations.none? { |r| r.issue_from_id == target.id || r.issue_to_id == target.id }
        end

        should "be idempotent when removing a relation that does not exist" do
          issue = Issue.find(1)
          assert_nothing_raised do
            @provider.update_issue(issue_id: issue.id, relations_to_remove: [{ issue_id: 99 }])
          end
        end
      end
    end
  end
end
