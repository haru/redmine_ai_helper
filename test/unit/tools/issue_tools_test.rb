require File.expand_path("../../../test_helper", __FILE__)

class IssueToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields

  def setup
    @provider = RedmineAiHelper::Tools::IssueTools.new
  end

  context "IssueTool" do
    context "read_issues" do
      should "return issues" do
        issue = Issue.find(1)
        response = @provider.read_issues(issue_ids: [1])
        assert_equal 1, response[:issues].size
        assert_equal issue.id, response[:issues].first[:id]
      end

      should "return error with invalid id" do
        assert_raises(RuntimeError, "Issue not found") do
          @provider.read_issues(issue_ids: [999])
        end
      end

      should "return RubyLLM::Content when issue has image attachments" do
        issue = Issue.find(1)
        image_path = File.join(Dir.tmpdir, "test_image.png")
        File.write(image_path, "fake png content")
        @provider.stubs(:image_attachment_paths).returns([image_path])

        response = @provider.read_issues(issue_ids: [issue.id])

        assert_instance_of RubyLLM::Content, response
        assert_includes response.text, issue.subject
        assert_equal 1, response.attachments.size
      ensure
        File.delete(image_path) if File.exist?(image_path)
      end

      should "return Hash when issue has no image attachments" do
        issue = Issue.find(1)
        @provider.stubs(:image_attachment_paths).returns([])

        response = @provider.read_issues(issue_ids: [issue.id])

        assert_instance_of Hash, response
        assert response[:issues].is_a?(Array)
      end
    end

    context "capable_issue_properties" do
      should "return properties with project id" do
        project = Project.find(1)
        response = @provider.capable_issue_properties(project_id: 1)
        assert_equal project.trackers.size, response[:trackers].size
        assert_equal project.issue_categories.size, response[:categories].size
      end

      should "return properties with project name" do
        project = Project.find(1)
        response = @provider.capable_issue_properties(project_name: project.name)
        assert_equal project.trackers.size, response[:trackers].size
        assert_equal project.issue_categories.size, response[:categories].size
      end

      should "return properties with project identifier" do
        project = Project.find(1)
        response = @provider.capable_issue_properties(project_identifier: project.identifier)
        assert_equal project.trackers.size, response[:trackers].size
        assert_equal project.issue_categories.size, response[:categories].size
      end

      should "return error with invalid project" do
        assert_raises(RuntimeError, "No id or name or Identifier specified.") do
          @provider.capable_issue_properties(project_id: 999)
        end

        assert_raises(RuntimeError, "Project not found.") do
          @provider.capable_issue_properties(project_id: 999)
        end
      end
    end

    context "validate_new_issue" do
      should "validate issue" do
        User.current = User.find(1)
        response = @provider.validate_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")
        assert response[:issue_id].nil?
      end

      should "return error with invalid project" do
        assert_raises(RuntimeError, "Validation failed") do
          @provider.validate_new_issue(project_id: 999, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")
        end
      end
    end

    context "validate_update_issue" do
      should "validate issue" do
        issue = Issue.find(1)
        original_subject = issue.subject
        @provider.validate_update_issue(issue_id: 1, subject: "test issue")
        assert_equal original_subject, Issue.find(issue.id).subject
      end

      should "return error with invalid issue" do
        assert_raises(RuntimeError, "Issue not found") do
          @provider.validate_update_issue(issue_id: 999, subject: "test issue")
        end
      end
    end
  end
end
