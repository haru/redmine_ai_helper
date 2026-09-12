require File.expand_path("../../../test_helper", __FILE__)

class IssueToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields,
           :enabled_modules, :roles, :members, :member_roles

  def setup
    @provider = RedmineAiHelper::Tools::IssueTools.new
  end

  context "IssueTool" do
    context "read_issues" do
      setup do
        # read_issues requires the ai_helper module and the view_ai_helper permission
        # on the issue's project (project 1, via jsmith's role 1).
        @previous_user = User.current
        User.current = User.find(2)
        EnabledModule.create!(project_id: 1, name: "ai_helper")
        Role.find(1).add_permission!(:view_ai_helper)
      end

      teardown do
        User.current = @previous_user
      end

      should "return issues" do
        issue = Issue.find(1)
        response = @provider.read_issues(issue_ids: [ 1 ])

        assert_equal 1, response[:issues].size
        assert_equal issue.id, response[:issues].first[:id]
      end

      should "return error with invalid id" do
        assert_raises(RuntimeError, "Issue not found") do
          @provider.read_issues(issue_ids: [ 999 ])
        end
      end

      should "always return Hash regardless of image attachments" do
        issue = Issue.find(1)

        response = @provider.read_issues(issue_ids: [ issue.id ])

        assert_instance_of Hash, response
        assert_kind_of Array, response[:issues]
      end
    end

    context "read_issues project scope" do
      setup do
        @plain_project = Project.find(3) # ai_helper module not enabled, public
        @tracker = Tracker.find(1)
        @plain_project.trackers << @tracker unless @plain_project.trackers.include?(@tracker)
        @user = User.find(2)
        @previous_user = User.current
        User.current = @user
        @issue = Issue.create!(project: @plain_project, tracker: @tracker, subject: "Module Disabled Project Issue",
          author: @user, status: IssueStatus.first, priority: IssuePriority.first)
      end

      teardown do
        User.current = @previous_user
        @issue&.destroy
      end

      should "raise Issue not found for an issue whose project has the ai_helper module disabled when all_projects_scope is OFF" do
        AiHelperSetting.stubs(:all_projects_scope?).returns(false)

        assert_raises(RuntimeError, "Issue not found") do
          @provider.read_issues(issue_ids: [ @issue.id ])
        end
      end

      should "return the issue from a module-disabled project when all_projects_scope is ON" do
        AiHelperSetting.stubs(:all_projects_scope?).returns(true)

        response = @provider.read_issues(issue_ids: [ @issue.id ])

        ids = response[:issues].map { |i| i[:id] }
        assert_includes ids, @issue.id
      end

      should "return only the accessible issues when mixing accessible and module-disabled projects, with all_projects_scope OFF" do
        AiHelperSetting.stubs(:all_projects_scope?).returns(false)
        accessible_issue = Issue.find(1) # project 1, no ai_helper module either, but included via module-enabled below
        EnabledModule.create!(project_id: 1, name: "ai_helper")
        Role.find(1).add_permission!(:view_ai_helper)

        response = @provider.read_issues(issue_ids: [ accessible_issue.id, @issue.id ])

        ids = response[:issues].map { |i| i[:id] }
        assert_includes ids, accessible_issue.id
        assert_not_includes ids, @issue.id
      end
    end

    context "capable_issue_properties" do
      setup do
        @previous_user = User.current
        User.current = User.find(2)
        EnabledModule.create!(project_id: 1, name: "ai_helper")
        Role.find(1).add_permission!(:view_ai_helper)
      end

      teardown do
        User.current = @previous_user
      end

      should "raise when the project's ai_helper module is disabled and all_projects_scope is OFF" do
        AiHelperSetting.stubs(:all_projects_scope?).returns(false)
        EnabledModule.where(project_id: 1, name: "ai_helper").destroy_all

        assert_raises(RuntimeError) do
          @provider.capable_issue_properties(project_id: 1)
        end
      end

      should "return properties for a module-disabled project when all_projects_scope is ON" do
        AiHelperSetting.stubs(:all_projects_scope?).returns(true)
        EnabledModule.where(project_id: 1, name: "ai_helper").destroy_all
        project = Project.find(1)

        response = @provider.capable_issue_properties(project_id: 1)

        assert_equal project.trackers.size, response[:trackers].size
      end

      should "raise for a project that is not visible to the current user" do
        User.current = User.anonymous
        Project.find(1).update!(is_public: false)

        assert_raises(RuntimeError) do
          @provider.capable_issue_properties(project_id: 1)
        end
      end

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
      setup do
        # validate_new_issue delegates to IssueUpdateTools#create_new_issue, which
        # requires the ai_helper module on the target project.
        EnabledModule.create!(project_id: 1, name: "ai_helper")
      end

      should "validate issue" do
        User.current = User.find(1)
        response = @provider.validate_new_issue(project_id: 1, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")

        assert_nil response[:issue_id]
      end

      should "return error with invalid project" do
        assert_raises(RuntimeError, "Validation failed") do
          @provider.validate_new_issue(project_id: 999, tracker_id: 1, status_id: 1, subject: "test issue", description: "test description")
        end
      end
    end

    context "validate_update_issue" do
      setup do
        # validate_update_issue delegates to IssueUpdateTools#update_issue, which
        # requires the ai_helper module and the view_ai_helper permission on the
        # issue's project.
        EnabledModule.create!(project_id: 1, name: "ai_helper")
        @previous_user = User.current
        User.current = User.find(1)
      end

      teardown do
        User.current = @previous_user
      end

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
