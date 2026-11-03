# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require_relative "no_delete_tools_assertions"

class CategoryToolsTest < ActiveSupport::TestCase
  include NoDeleteToolsAssertions

  fixtures :projects, :enabled_modules, :users, :members, :member_roles, :roles,
           :groups_users, :issue_categories, :issues, :trackers, :projects_trackers,
           :issue_statuses, :enumerations

  setup do
    @provider = RedmineAiHelper::Tools::CategoryTools.new
    @project = Project.find(1)
    EnabledModule.create!(project_id: @project.id, name: "ai_helper") unless @project.module_enabled?(:ai_helper)
    Role.find(1).add_permission!(:view_ai_helper)
    Role.find(2).add_permission!(:view_ai_helper)
    @previous_user = User.current
    User.current = User.find(2) # jsmith: Manager in project 1
  end

  teardown do
    User.current = @previous_user
  end

  context "tool name length" do
    should "keep every generated tool name within 64 characters" do
      RedmineAiHelper::Tools::CategoryTools.tool_classes.each do |tool_class|
        assert_operator tool_class.new.name.length, :<=, 64,
          "#{tool_class.name} exceeds the 64 character tool name limit: #{tool_class.new.name}"
      end
    end
  end

  context "list_categories" do
    should "return the categories and the assignable principals" do
      result = @provider.list_categories(project_id: @project.id)

      assert_equal @project.id, result[:project_id]
      assert_equal @project.issue_categories.order(:id).pluck(:id), result[:categories].map { |c| c[:id] }.sort
      printing = result[:categories].find { |c| c[:name] == "Printing" }
      assert_equal({ id: 2, name: User.find(2).name, type: "user" }, printing[:assigned_to])
      assert_equal @project.assignable_users.map(&:id).sort, result[:assignable_principals].map { |p| p[:id] }.sort
      assert(result[:assignable_principals].all? { |p| %w[user group].include?(p[:type]) })
    end

    should "return assigned_to null for a category without an assignee" do
      result = @provider.list_categories(project_id: @project.id)

      recipes = result[:categories].find { |c| c[:name] == "Recipes" }
      assert_nil recipes[:assigned_to]
    end

    should "reject when the issue_tracking module is disabled" do
      EnabledModule.where(project_id: @project.id, name: "issue_tracking").destroy_all

      result = @provider.list_categories(project_id: @project.id)

      assert_equal({ error: "Issue tracking module is not enabled on project #{@project.id}" }, result)
    end

    should "reject a project that does not exist" do
      result = @provider.list_categories(project_id: 99_999)

      assert_equal({ error: "Project not found. id = 99999" }, result)
    end

    should "reject a project that is not available to AI Helper" do
      EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

      result = @provider.list_categories(project_id: @project.id)

      assert_equal({ error: "Project is not accessible: id = #{@project.id}" }, result)
    end
  end

  context "create_category" do
    should "create a category with a name only" do
      assert_difference "IssueCategory.count", 1 do
        result = @provider.create_category(project_id: @project.id, name: "UI")

        assert_equal "UI", result[:name]
        assert_equal({ id: @project.id, name: @project.name }, result[:project])
        assert_nil result[:assigned_to]
        assert_equal @project.id, IssueCategory.find(result[:id]).project_id
      end
    end

    should "create a category with an assignee" do
      result = @provider.create_category(project_id: @project.id, name: "UI", assigned_to_id: 2)

      assert_equal({ id: 2, name: User.find(2).name, type: "user" }, result[:assigned_to])
      assert_equal 2, IssueCategory.find(result[:id]).assigned_to_id
    end

    should "reject without manage_categories permission and create nothing" do
      Role.find(1).remove_permission!(:manage_categories)
      Role.find(2).remove_permission!(:manage_categories)

      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "UI")

        assert_equal({ error: "Permission denied: manage_categories on project #{@project.id}" }, result)
      end
    end

    should "reject when the issue_tracking module is disabled" do
      EnabledModule.where(project_id: @project.id, name: "issue_tracking").destroy_all

      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "UI")

        assert_equal({ error: "Issue tracking module is not enabled on project #{@project.id}" }, result)
      end
    end

    should "reject an assignee who is not assignable in the project" do
      # user 9 is not a member of project 1
      assert_not @project.assignable_users.map(&:id).include?(9)

      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "UI", assigned_to_id: 9)

        assert_equal({ error: "Assignee not allowed: id = 9 (must be an assignable member of the project)" }, result)
      end
    end

    should "reject a duplicate name" do
      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "Printing")

        assert_equal({ error: "Failed to create category: Name has already been taken" }, result)
      end
    end

    should "reject an empty name" do
      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "")

        assert_match(/\AFailed to create category: Name/, result[:error])
      end
    end

    should "reject a closed project" do
      @project.update!(status: Project::STATUS_CLOSED)
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)
      EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

      assert_no_difference "IssueCategory.count" do
        result = @provider.create_category(project_id: @project.id, name: "UI")

        assert_equal({ error: "Project is closed: id = #{@project.id}" }, result)
      end
    end
  end

  context "update_category" do
    setup do
      @category = IssueCategory.find(1) # Printing, assigned to user 2, project 1
    end

    should "change only the given name" do
      result = @provider.update_category(category_id: @category.id, name: "Press")

      assert_equal "Press", result[:name]
      assert_equal({ id: 2, name: User.find(2).name, type: "user" }, result[:assigned_to])
      assert_equal "Press", @category.reload.name
      assert_equal 2, @category.assigned_to_id
    end

    should "change only the given assignee" do
      other = @project.assignable_users.find { |principal| principal.id != 2 }
      assert other, "the fixture needs a second assignable principal"

      result = @provider.update_category(category_id: @category.id, assigned_to_id: other.id)

      assert_equal other.id, result[:assigned_to][:id]
      assert_equal "Printing", @category.reload.name
      assert_equal other.id, @category.assigned_to_id
    end

    should "remove the assignee with clear_assigned_to" do
      result = @provider.update_category(category_id: @category.id, clear_assigned_to: true)

      assert_nil result[:assigned_to]
      assert_nil @category.reload.assigned_to_id
      assert_equal "Printing", @category.name
    end

    should "save nothing and return the current state when no field is given" do
      IssueCategory.any_instance.expects(:save).never

      result = @provider.update_category(category_id: @category.id)

      assert_equal "Printing", result[:name]
      assert_equal 2, result[:assigned_to][:id]
    end

    should "reject a category that does not exist" do
      result = @provider.update_category(category_id: 99_999, name: "X")

      assert_equal({ error: "Category not found. id = 99999" }, result)
    end

    should "judge the project of the category, not another project" do
      # category 3 belongs to project 2, where jsmith has no AI Helper access
      Project.find(2).enabled_modules.where(name: "ai_helper").destroy_all
      AiHelperSetting.stubs(:all_projects_scope?).returns(false)
      before = IssueCategory.find(3).attributes

      result = @provider.update_category(category_id: 3, name: "Hijacked")

      assert_equal({ error: "Project is not accessible: id = 2" }, result)
      assert_equal before, IssueCategory.find(3).attributes
    end

    should "reject assigned_to_id together with clear_assigned_to" do
      result = @provider.update_category(category_id: @category.id, assigned_to_id: 2, clear_assigned_to: true)

      assert_equal({ error: "assigned_to_id and clear_assigned_to cannot be used together" }, result)
      assert_equal 2, @category.reload.assigned_to_id
    end

    should "reject an assignee who is not assignable" do
      result = @provider.update_category(category_id: @category.id, assigned_to_id: 9)

      assert_equal({ error: "Assignee not allowed: id = 9 (must be an assignable member of the project)" }, result)
      assert_equal 2, @category.reload.assigned_to_id
    end

    should "reject renaming to an existing name" do
      result = @provider.update_category(category_id: @category.id, name: "Recipes")

      assert_equal({ error: "Failed to update category: Name has already been taken" }, result)
      assert_equal "Printing", @category.reload.name
    end

    should "reject an empty name" do
      result = @provider.update_category(category_id: @category.id, name: "")

      assert_match(/\AFailed to update category: Name/, result[:error])
      assert_equal "Printing", @category.reload.name
    end

    should "reject without manage_categories permission" do
      Role.find(1).remove_permission!(:manage_categories)
      Role.find(2).remove_permission!(:manage_categories)

      result = @provider.update_category(category_id: @category.id, name: "Press")

      assert_equal({ error: "Permission denied: manage_categories on project #{@project.id}" }, result)
      assert_equal "Printing", @category.reload.name
    end
  end

  context "no destructive tools" do
    should "not define a delete, destroy, or archive tool" do
      assert_no_destructive_tool_names(RedmineAiHelper::Tools::CategoryTools)
    end

    should "not call a destructive method in the tool code" do
      assert_destructive_calls_only(RedmineAiHelper::Tools::CategoryTools, allowed: [])
    end
  end
end
