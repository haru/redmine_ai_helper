# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/project_write_guard"

# Test host that mixes in the guard module the same way the tool classes do.
class ProjectWriteGuardHost < RedmineAiHelper::BaseTools
  include RedmineAiHelper::Util::ProjectWriteGuard
end

class RedmineAiHelper::Util::ProjectWriteGuardTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules, :users, :members, :member_roles, :roles

  setup do
    @guard = ProjectWriteGuardHost.new
    @project = Project.find(1)
    unless @project.module_enabled?(:ai_helper)
      EnabledModule.create!(project: @project, name: "ai_helper")
    end
    Role.find(1).add_permission!(:view_ai_helper)
    Role.find(2).add_permission!(:view_ai_helper)
    @previous_user = User.current
  end

  teardown do
    User.current = @previous_user
  end

  def close_project(project)
    project.update!(status: Project::STATUS_CLOSED)
  end

  # Make a closed project pass accessible_project?: the data-access decision is
  # all_projects_scope when the ai_helper module is disabled, so it does not run
  # allowed_to?(:view_ai_helper), which a closed project would reject.
  def make_closed_project_accessible(project)
    AiHelperSetting.stubs(:all_projects_scope?).returns(true)
    EnabledModule.where(project_id: project.id, name: "ai_helper").destroy_all
    close_project(project)
  end

  context "writable_project! (write fetch)" do
    should "raise when project_id is nil" do
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: nil, permission: :manage_versions)
      end

      assert_equal "project_id is required", error.message
    end

    should "raise Project not found for a nonexistent project" do
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: 999, permission: :manage_versions)
      end

      assert_equal "Project not found. id = 999", error.message
    end

    should "raise Project not found for an invisible project" do
      # Project 5 is private; user 4 has no membership and cannot see it.
      User.current = User.find(4)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: 5, permission: :manage_versions)
      end

      assert_equal "Project not found. id = 5", error.message
    end

    should "raise not accessible when the project has no ai_helper module and scope is off" do
      # Project 3 is public (visible to admin) but the ai_helper module is not enabled.
      EnabledModule.where(project_id: 3, name: "ai_helper").destroy_all
      AiHelperSetting.stubs(:all_projects_scope?).returns(false)
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: 3, permission: :edit_project)
      end

      assert_equal "Project is not accessible: id = 3", error.message
    end

    should "raise Project is closed for a closed project" do
      make_closed_project_accessible(@project)
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: @project.id, permission: :manage_versions)
      end

      assert_equal "Project is closed: id = #{@project.id}", error.message
    end

    should "raise Issue tracking module is not enabled before the permission check" do
      # User 3 (Developer in project 1) lacks both the module and manage_members;
      # the module message must win because it is checked first.
      EnabledModule.where(project_id: @project.id, name: "issue_tracking").destroy_all
      User.current = User.find(3)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: @project.id, permission: :manage_members, require_issue_tracking: true)
      end

      assert_equal "Issue tracking module is not enabled on project #{@project.id}", error.message
    end

    should "raise Permission denied when the user lacks the permission on an open project" do
      # User 3 sees the public project 1 (accessible), which is open, but the
      # Developer role is stripped of manage_members for this test.
      Role.find(2).remove_permission!(:manage_members)
      User.current = User.find(3)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: @project.id, permission: :manage_members)
      end

      assert_equal "Permission denied: manage_members on project #{@project.id}", error.message
    end

    should "return the project when every guard passes" do
      User.current = User.find(1)

      result = @guard.writable_project!(project_id: @project.id, permission: :manage_versions)

      assert_equal @project.id, result.id
    end

    should "return the project when issue_tracking is enabled and permission is granted" do
      User.current = User.find(1)

      result = @guard.writable_project!(project_id: @project.id, permission: :manage_categories, require_issue_tracking: true)

      assert_equal @project.id, result.id
    end
  end

  context "permission argument type" do
    should "refuse a write fetch without a permission" do
      User.current = User.find(1)

      error = assert_raises(ArgumentError) { @guard.writable_project!(project_id: @project.id, permission: nil) }

      assert_equal "permission is required for a write fetch", error.message
    end

    should "refuse a permission that is neither a Symbol nor a Hash" do
      User.current = User.find(1)

      [ "manage_members", 1 ].each do |bad|
        error = assert_raises(ArgumentError, "writable #{bad.inspect}") { @guard.writable_project!(project_id: @project.id, permission: bad) }
        assert_equal "permission must be a Symbol or a Hash: #{bad.inspect}", error.message
        error = assert_raises(ArgumentError, "readable #{bad.inspect}") { @guard.readable_project!(project_id: @project.id, permission: bad) }
        assert_equal "permission must be a Symbol or a Hash: #{bad.inspect}", error.message
      end
    end

    should "accept a Hash permission and name it in the denial message" do
      User.current = User.find(2)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.writable_project!(project_id: @project.id, permission: { controller: "projects", action: "no_such_action" })
      end

      assert_equal "Permission denied: projects/no_such_action on project #{@project.id}", error.message
    end
  end

  context "readable_project! (read fetch)" do
    should "not judge the closed state" do
      make_closed_project_accessible(@project)
      User.current = User.find(1)

      # A closed project rejects write permissions in allowed_to? itself, so the
      # read fetch must use a read permission to prove the closed guard is skipped.
      result = @guard.readable_project!(project_id: @project.id, permission: :view_issues)

      assert_equal @project.id, result.id
    end

    should "raise when project_id is nil" do
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.readable_project!(project_id: nil, permission: :manage_members)
      end

      assert_equal "project_id is required", error.message
    end

    should "raise Project not found for an invisible project" do
      User.current = User.find(4)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.readable_project!(project_id: 5, permission: :manage_members)
      end

      assert_equal "Project not found. id = 5", error.message
    end

    should "raise not accessible when the project has no ai_helper module and scope is off" do
      EnabledModule.where(project_id: 3, name: "ai_helper").destroy_all
      AiHelperSetting.stubs(:all_projects_scope?).returns(false)
      User.current = User.find(1)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.readable_project!(project_id: 3, permission: :manage_members)
      end

      assert_equal "Project is not accessible: id = 3", error.message
    end

    should "raise Permission denied when the user lacks the permission" do
      Role.find(2).remove_permission!(:manage_members)
      User.current = User.find(3)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.readable_project!(project_id: @project.id, permission: :manage_members)
      end

      assert_equal "Permission denied: manage_members on project #{@project.id}", error.message
    end

    should "skip the permission check when no permission is required" do
      Role.find(2).remove_permission!(:manage_members)
      User.current = User.find(3)

      result = @guard.readable_project!(project_id: @project.id, permission: nil)

      assert_equal @project.id, result.id
    end

    should "still judge visibility when no permission is required" do
      User.current = User.find(4)

      error = assert_raises(RedmineAiHelper::BaseTools::UserError) do
        @guard.readable_project!(project_id: 5, permission: nil)
      end

      assert_equal "Project not found. id = 5", error.message
    end
  end
end
