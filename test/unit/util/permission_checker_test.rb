require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/permission_checker"

class RedmineAiHelper::Util::PermissionCheckerTest < ActiveSupport::TestCase
  context "PermissionChecker.module_enabled?" do
    setup do
      @project = Project.find(1)
      @user = User.find(2)
      @previous_user = User.current
    end

    teardown do
      User.current = @previous_user
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

  context "PermissionChecker.data_accessible?" do
    setup do
      @project = Project.find(1)
      @user = User.find(2)
      @previous_user = User.current
    end

    teardown do
      User.current = @previous_user
    end

    should "return false when project is nil" do
      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: nil, user: @user, all_projects_scope: true)
    end

    should "return false when project is not visible to the user, module enabled" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(true)
      @project.stubs(:visible?).with(@user).returns(false)

      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: true)
    end

    should "return false when project is not visible to the user, module disabled, all_projects_scope ON" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(false)
      @project.stubs(:visible?).with(@user).returns(false)

      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: true)
    end

    should "return true when module enabled, visible, and user has view_ai_helper permission" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(true)
      @project.stubs(:visible?).with(@user).returns(true)
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)

      assert_equal true, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: false)
      assert_equal true, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: true)
    end

    should "return false when module enabled, visible, but user lacks view_ai_helper permission (all_projects_scope does not widen module-enabled projects)" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(true)
      @project.stubs(:visible?).with(@user).returns(true)
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(false)

      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: false)
      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: true)
    end

    should "return false when module disabled and all_projects_scope OFF, even if visible" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(false)
      @project.stubs(:visible?).with(@user).returns(true)

      assert_equal false, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: false)
    end

    should "return true when module disabled, visible, and all_projects_scope ON, without checking view_ai_helper" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(false)
      @project.stubs(:visible?).with(@user).returns(true)
      @user.expects(:allowed_to?).with(:view_ai_helper, @project).never

      assert_equal true, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user, all_projects_scope: true)
    end

    should "default all_projects_scope to AiHelperSetting.all_projects_scope?" do
      @project.stubs(:module_enabled?).with(:ai_helper).returns(false)
      @project.stubs(:visible?).with(@user).returns(true)
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)

      assert_equal true, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, user: @user)
    end

    should "default user to User.current" do
      User.current = @user
      @project.stubs(:module_enabled?).with(:ai_helper).returns(true)
      @project.stubs(:visible?).with(@user).returns(true)
      @user.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)

      assert_equal true, RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: @project, all_projects_scope: false)
    end
  end

  context "PermissionChecker.data_access_condition" do
    setup do
      @user = User.find(2)
      @previous_user = User.current
    end

    teardown do
      User.current = @previous_user
    end

    should "AND the visible condition with the module condition when all_projects_scope is OFF" do
      result = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: false)

      assert_includes result, Project.visible_condition(@user)
      assert_includes result, Project.allowed_to_condition(@user, :view_ai_helper)
    end

    should "AND the visible condition with an OR-ed NOT EXISTS enabled_modules clause when all_projects_scope is ON" do
      base = Project.allowed_to_condition(@user, :view_ai_helper)
      result = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: true)

      assert_includes result, Project.visible_condition(@user)
      assert_includes result, base
      assert_match(/NOT EXISTS/, result)
      assert_match(/enabled_modules/, result)
      assert_match(/name = 'ai_helper'/, result)
    end

    should "default all_projects_scope to AiHelperSetting.all_projects_scope?" do
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)
      result = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user)

      assert_match(/NOT EXISTS/, result)
    end

    should "default user to User.current" do
      User.current = @user
      result = RedmineAiHelper::Util::PermissionChecker.data_access_condition(all_projects_scope: false)

      assert_includes result, Project.visible_condition(@user)
      assert_includes result, Project.allowed_to_condition(@user, :view_ai_helper)
    end
  end

  context "PermissionChecker.data_access_condition applied to real queries" do
    fixtures :projects, :enabled_modules, :users, :roles, :members, :member_roles, :issues

    setup do
      @user = User.find(2) # jsmith: member of public project 1 and private project 2
      @previous_user = User.current
      User.current = @user
      Role.find(1).add_permission!(:view_ai_helper)
      Role.find(2).add_permission!(:view_ai_helper)
      EnabledModule.create!(project_id: 1, name: "ai_helper")
      @previous_scope = AiHelperSetting.setting.all_projects_scope
    end

    teardown do
      User.current = @previous_user
      AiHelperSetting.setting.update_column(:all_projects_scope, @previous_scope)
    end

    should "exclude a private project the user is not a member of when all_projects_scope is ON" do
      AiHelperSetting.setting.update_column(:all_projects_scope, true)
      private_project = Project.create!(name: "Checker Private #{Time.now.to_i}#{rand(10000)}", identifier: "checker-private-#{Time.now.to_i}#{rand(10000)}", is_public: false)
      condition = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: true)

      assert_not_includes Project.where(condition).ids, private_project.id
    ensure
      private_project&.destroy
    end

    should "exclude a module-enabled project whose role lacks view_ai_helper even when all_projects_scope is ON" do
      Role.find(1).remove_permission!(:view_ai_helper)
      condition_on = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: true)
      condition_off = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: false)

      assert_not_includes Project.where(condition_on).ids, Project.find(1).id
      assert_not_includes Project.where(condition_off).ids, Project.find(1).id
    end

    should "keep a module-enabled project whose role holds view_ai_helper when all_projects_scope is ON" do
      AiHelperSetting.setting.update_column(:all_projects_scope, true)
      condition = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: true)

      assert_includes Project.where(condition).ids, Project.find(1).id
    end

    should "include a module-disabled, visible project when all_projects_scope is ON" do
      AiHelperSetting.setting.update_column(:all_projects_scope, true)
      condition = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: true)

      assert_includes Project.where(condition).ids, Project.find(3).id
    end

    should "exclude a module-disabled project when all_projects_scope is OFF" do
      condition = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: false)

      assert_not_includes Project.where(condition).ids, Project.find(3).id
    end

    should "agree with data_accessible? for every fixture project, ON and OFF (parity)" do
      [ true, false ].each do |flag|
        condition = RedmineAiHelper::Util::PermissionChecker.data_access_condition(@user, all_projects_scope: flag)
        sql_ids = Project.where(condition).order(:id).ids
        ruby_ids = Project.order(:id).select { |p|
          RedmineAiHelper::Util::PermissionChecker.data_accessible?(project: p, user: @user, all_projects_scope: flag)
        }.map(&:id)

        assert_equal ruby_ids, sql_ids, "SQL condition and data_accessible? disagree with all_projects_scope=#{flag}"
      end
    end
  end

  context "PermissionChecker.accessible_projects" do
    fixtures :projects, :enabled_modules, :users, :roles, :members, :member_roles

    setup do
      @user = User.find(2)
      @previous_user = User.current
      User.current = @user
      Role.find(1).add_permission!(:view_ai_helper)
      EnabledModule.create!(project_id: 1, name: "ai_helper")
    end

    teardown do
      User.current = @previous_user
    end

    should "filter the given relation down to accessible projects and preload enabled_modules" do
      private_project = Project.create!(name: "Checker Private 2 #{Time.now.to_i}#{rand(10000)}", identifier: "checker-private-2-#{Time.now.to_i}#{rand(10000)}", is_public: false)
      result = RedmineAiHelper::Util::PermissionChecker.accessible_projects(Project.where(id: [ 1, private_project.id ]))

      assert_equal [ Project.find(1).id ], result.map(&:id)
      assert result.first.association(:enabled_modules).loaded?
    ensure
      private_project&.destroy
    end
  end
end
