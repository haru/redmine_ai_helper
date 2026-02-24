require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/permission_checker"

class RedmineAiHelper::Util::PermissionCheckerTest < ActiveSupport::TestCase
  context "PermissionChecker.module_enabled?" do
    setup do
      @project = Project.find(1)
      @user = User.find(2)
    end

    should "return false when project is nil" do
      assert_not RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: nil, user: @user)
    end

    should "return false when project has no id (unsaved)" do
      project = Project.new
      @user.stubs(:allowed_to?).with(:view_ai_helper, project).returns(true)
      assert_not RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: project, user: @user)
    end

    should "return false when user does not have permission" do
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(false)
      assert_not RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, user: @user)
    end

    should "return true when project is persisted and user has permission" do
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, user: @user)
    end

    should "default to User.current when user is not specified" do
      User.current = @user
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project)
    end

    should "default to :view_ai_helper when permission is not specified" do
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, user: @user)
    end

    should "use custom permission when specified as symbol" do
      @user.stubs(:allowed_to?).with(:edit_ai_helper, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, user: @user, permission: :edit_ai_helper)
    end

    should "use custom permission when specified as hash" do
      permission = { controller: :ai_helper, action: :chat_form }
      @user.stubs(:allowed_to?).with(permission, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, user: @user, permission: permission)
    end

    should "allow specifying permission without user (uses User.current)" do
      User.current = @user
      permission = { controller: :ai_helper, action: :issue_summary }
      @user.stubs(:allowed_to?).with(permission, @project).returns(true)
      assert RedmineAiHelper::Util::PermissionChecker.module_enabled?(project: @project, permission: permission)
    end
  end
end
