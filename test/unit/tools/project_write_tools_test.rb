# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require_relative "no_delete_tools_assertions"

class ProjectWriteToolsTest < ActiveSupport::TestCase
  include NoDeleteToolsAssertions

  fixtures :projects, :enabled_modules, :users, :members, :member_roles, :roles,
           :custom_fields, :custom_values, :projects_trackers, :trackers,
           :issue_categories, :issues, :issue_statuses, :enumerations

  setup do
    @provider = RedmineAiHelper::Tools::ProjectWriteTools.new
    @project = Project.find(1)
    EnabledModule.create!(project_id: @project.id, name: "ai_helper") unless @project.module_enabled?(:ai_helper)
    Role.find(1).add_permission!(:view_ai_helper)
    Role.find(2).add_permission!(:view_ai_helper)
    @previous_user = User.current
    User.current = User.find(1) # admin
  end

  teardown do
    User.current = @previous_user
  end

  # A givable role without the module-selection, publicity, or member-management
  # permissions, used as the default role of non-admin creators.
  def limited_role
    @limited_role ||= Role.create!(name: "Limited Creator", permissions: [ :view_issues ])
  end

  def project_to_hash_for_assert(project)
    {
      id: project.id, name: project.name, identifier: project.identifier,
      is_public: project.is_public, inherit_members: project.inherit_members, status: project.status
    }
  end

  context "tool name length" do
    should "keep every generated tool name within 64 characters" do
      RedmineAiHelper::Tools::ProjectWriteTools.tool_classes.each do |tool_class|
        assert_operator tool_class.new.name.length, :<=, 64,
          "#{tool_class.name} exceeds the 64 character tool name limit: #{tool_class.new.name}"
      end
    end
  end

  context "add_trackers" do
    setup do
      # the fixture assigns trackers 1, 2, 3 to project 1; start from 1 and 2
      @project.tracker_ids = [ 1, 2 ]
    end

    should "assign a tracker and keep the existing assignments" do
      # project 1 has trackers 1 and 2
      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [ 3 ])

      assert_equal [ 1, 2, 3 ], @project.reload.tracker_ids.sort
      assert_equal [], result[:unchanged]
      assert_equal [ 1, 2, 3 ], result[:trackers].map { |t| t[:id] }.sort
    end

    should "save nothing when the tracker is already assigned" do
      Project.any_instance.expects(:save).never

      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [ 1 ])

      assert_equal([ 1 ], result[:unchanged].map { |t| t[:id] })
    end

    should "reject empty tracker_ids" do
      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [])

      assert result[:error].present?
    end

    should "reject when one of the tracker ids does not exist" do
      before = @project.tracker_ids

      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [ 3, 999 ])

      assert_match(/999/, result[:error])
      assert_equal before, @project.reload.tracker_ids
    end

    should "reject without edit_project permission and change nothing" do
      Role.find(1).remove_permission!(:edit_project)
      Role.find(2).remove_permission!(:edit_project)
      User.current = User.find(2)
      before = @project.tracker_ids

      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [ 3 ])

      assert_equal({ error: "Permission denied: edit_project on project #{@project.id}" }, result)
      assert_equal before, @project.reload.tracker_ids
    end

    should "reject when the issue_tracking module is disabled" do
      EnabledModule.where(project_id: @project.id, name: "issue_tracking").destroy_all

      result = @provider.add_trackers(project_id: @project.id, tracker_ids: [ 3 ])

      assert_equal({ error: "Issue tracking module is not enabled on project #{@project.id}" }, result)
    end

    should "reject a closed project" do
      closed = Project.create!(name: "Closed Tracker Test", identifier: "closed-tracker-test", status: Project::STATUS_CLOSED)
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)

      result = @provider.add_trackers(project_id: closed.id, tracker_ids: [ 1 ])

      assert_equal({ error: "Project is closed: id = #{closed.id}" }, result)
    end
  end

  context "remove_trackers" do
    setup do
      @project.tracker_ids = [ 1, 2 ]
    end

    should "unassign a tracker without touching issues or the trackers themselves" do
      # project 1 has trackers 1 and 2; its issues use them
      tracker1_ids = Issue.where(project_id: @project.id, tracker_id: 1).pluck(:id)
      tracker2_ids = Issue.where(project_id: @project.id, tracker_id: 2).pluck(:id)
      assert tracker2_ids.any?, "the fixture issues on tracker 2 must exist for this test"
      tracker_count = Tracker.count

      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 2 ])

      assert_equal [ 1 ], @project.reload.tracker_ids
      assert_equal [], result[:unchanged]
      assert_not result.key?(:no_trackers)
      # SC-006: the issues keep their tracker and their count; Tracker records are untouched
      assert_equal tracker1_ids, Issue.where(project_id: @project.id, tracker_id: 1).pluck(:id)
      assert_equal tracker2_ids, Issue.where(project_id: @project.id, tracker_id: 2).pluck(:id)
      assert_equal tracker_count, Tracker.count
    end

    should "report no_trackers when the last tracker is unassigned" do
      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 1, 2 ])

      assert_equal [], @project.reload.tracker_ids
      assert_equal true, result[:no_trackers]
    end

    should "save nothing when the tracker is not assigned" do
      Project.any_instance.expects(:save).never

      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 3 ])

      assert_equal([ 3 ], result[:unchanged].map { |t| t[:id] })
    end

    should "reject without edit_project permission and change nothing" do
      Role.find(1).remove_permission!(:edit_project)
      Role.find(2).remove_permission!(:edit_project)
      User.current = User.find(2)
      before = @project.tracker_ids

      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 2 ])

      assert_equal({ error: "Permission denied: edit_project on project #{@project.id}" }, result)
      assert_equal before, @project.reload.tracker_ids
    end

    should "reject when the issue_tracking module is disabled" do
      EnabledModule.where(project_id: @project.id, name: "issue_tracking").destroy_all

      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 2 ])

      assert_equal({ error: "Issue tracking module is not enabled on project #{@project.id}" }, result)
    end

    should "reject empty tracker_ids and nonexistent ids" do
      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [])

      assert result[:error].present?

      before = @project.tracker_ids
      result = @provider.remove_trackers(project_id: @project.id, tracker_ids: [ 999 ])

      assert_match(/999/, result[:error])
      assert_equal before, @project.reload.tracker_ids
    end

    should "state the limits in the tool description" do
      schema = RedmineAiHelper::Tools::ProjectWriteTools.function_schemas.to_openai_format
      description = schema.find { |f| f[:function][:name].end_with?("__remove_trackers") }[:function][:description]

      assert_match(/existing issues (?:are|will not be)|not delete|remain unchanged/i, description)
      assert_match(/trackers themselves|the trackers are not/i, description)
      assert_match(/no tracker/i, description)
    end
  end

  context "update_modules" do
    should "disable only the given module and keep the others" do
      # project 1 has issue_tracking, news, wiki (plus ai_helper from setup)
      result = @provider.update_modules(project_id: @project.id, disable: [ "news" ])

      modules = @project.reload.enabled_module_names
      assert_not_includes modules, "news"
      assert_includes modules, "wiki" # not mentioned: unchanged
      assert_includes modules, "ai_helper" # not mentioned: unchanged
      assert_equal [], result[:unchanged]
    end

    should "save nothing when nothing changes" do
      Project.any_instance.expects(:save).never

      result = @provider.update_modules(project_id: @project.id, enable: [ "wiki" ])

      assert_equal [ "wiki" ], result[:unchanged]
    end

    should "keep the module data when disabling a module" do
      wiki = @project.wiki
      assert_not_nil wiki

      @provider.update_modules(project_id: @project.id, disable: [ "wiki" ])

      assert_not @project.reload.module_enabled?(:wiki)
      assert_equal wiki.id, Wiki.find(wiki.id).id # the wiki content survives
    end

    should "reject without select_project_modules permission and change nothing" do
      Role.find(1).remove_permission!(:select_project_modules)
      Role.find(2).remove_permission!(:select_project_modules)
      User.current = User.find(2)
      before = Project.find(@project.id).enabled_module_names

      result = @provider.update_modules(project_id: @project.id, enable: [ "boards" ])

      assert_equal({ error: "Permission denied: select_project_modules on project #{@project.id}" }, result)
      assert_equal before, Project.find(@project.id).enabled_module_names
    end

    should "reject when both lists are empty" do
      result = @provider.update_modules(project_id: @project.id, enable: [], disable: [])

      assert result[:error].present?
    end

    should "reject when the same module is enabled and disabled" do
      before = Project.find(@project.id).enabled_module_names

      result = @provider.update_modules(project_id: @project.id, enable: [ "wiki" ], disable: [ "wiki" ])

      assert result[:error].present?
      assert_equal before, @project.reload.enabled_module_names
    end

    should "reject an unknown module name with the available names" do
      before = Project.find(@project.id).enabled_module_names

      result = @provider.update_modules(project_id: @project.id, enable: [ "nonexistent_module" ])

      assert_match(/Unknown modules: nonexistent_module/, result[:error])
      assert_match(/Available modules:/, result[:error])
      assert_equal before, @project.reload.enabled_module_names
    end

    should "reject a closed project" do
      closed = Project.create!(name: "Closed Module Test", identifier: "closed-module-test", status: Project::STATUS_CLOSED)
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)

      result = @provider.update_modules(project_id: closed.id, enable: [ "boards" ])

      assert_equal({ error: "Project is closed: id = #{closed.id}" }, result)
    end

    should "require confirmation before disabling the ai_helper module in the tool description" do
      schema = RedmineAiHelper::Tools::ProjectWriteTools.function_schemas.to_openai_format
      description = schema.find { |f| f[:function][:name].end_with?("__update_modules") }[:function][:description]

      assert_match(/Always confirm with the user before/i, description)
      assert_match(/ai_helper/i, description)
    end
  end

  context "create_project" do
    should "create a project with name and identifier and report URL and module state" do
      assert_difference "Project.count", 1 do
        @result = @provider.create_project(name: "Customer Portal Renewal", identifier: "portal-renewal")
      end

      assert_equal "Customer Portal Renewal", @result[:name]
      assert_equal "portal-renewal", @result[:identifier]
      assert_equal "/projects/portal-renewal", @result[:url_for_project]
      assert_equal true, @result[:ai_helper_module_enabled]
      assert_equal true, @result[:ai_helper_accessible]
      assert_equal true, @result[:is_public] # admin: Redmine default
    end

    should "make the creator a member with the default role for non-admin creators" do
      User.current = User.find(2) # jsmith: add_project via the Manager role

      assert_difference "Project.count", 1 do
        assert_difference "Member.count", 1 do
          @result = @provider.create_project(name: "Creator Member Test", identifier: "creator-member")
        end
      end

      default_role = Project.default_member_role
      assert_equal({ id: default_role.id, name: default_role.name }, @result[:default_member_role])
      created = Project.find(@result[:id])
      member = created.memberships.find_by(user_id: 2)
      assert_not_nil member
      assert_equal [ default_role.id ], member.role_ids
    end

    should "return a null default_member_role for an admin creator" do
      @result = @provider.create_project(name: "Admin Creator Test", identifier: "admin-creator")

      assert_nil @result[:default_member_role]
      assert_equal 0, Project.find(@result[:id]).memberships.count
    end

    should "use the Redmine defaults for modules and trackers" do
      @result = @provider.create_project(name: "Defaults Test", identifier: "defaults-test")

      defaults = Project.new
      created = Project.find(@result[:id])
      # R-004: the creator (admin) may select modules, so ai_helper is added to the defaults
      assert_equal (defaults.enabled_module_names | [ "ai_helper" ]).sort, created.enabled_module_names.sort
      assert_equal defaults.tracker_ids.sort, created.tracker_ids.sort
    end

    should "add the ai_helper module when the creator may select modules" do
      @result = @provider.create_project(name: "Module Select Test", identifier: "module-select")

      assert_equal true, @result[:ai_helper_module_enabled]
      assert Project.find(@result[:id]).module_enabled?(:ai_helper)
    end

    should "not add the ai_helper module when the creator may not select modules" do
      # The role given to non-admin creators lacks select_project_modules
      Project.stubs(:default_member_role).returns(limited_role)
      User.current = User.find(2)

      assert_difference "Project.count", 1 do
        @result = @provider.create_project(name: "No Module Select Test", identifier: "no-module-select")
      end

      assert_equal false, @result[:ai_helper_module_enabled]
      assert_not Project.find(@result[:id]).module_enabled?(:ai_helper)
    end

    should "create a subproject when a parent is given" do
      parent = Project.create!(name: "Sub Parent", identifier: "sub-parent")
      EnabledModule.create!(project_id: parent.id, name: "ai_helper")

      @result = @provider.create_project(name: "Child Project", identifier: "child-project", parent_id: parent.id)

      assert_equal({ id: parent.id, name: parent.name }, @result[:parent])
      assert_equal parent.id, Project.find(@result[:id]).reload.parent_id
    end

    should "reject a top-level creation without add_project" do
      User.current = User.find(4) # rhill: no global add_project

      result = @provider.create_project(name: "No Permission Test", identifier: "no-permission")

      assert_equal({ error: "Permission denied: add_project (top-level project)" }, result)
    end

    should "reject a subproject creation without add_subprojects on the parent" do
      parent = Project.create!(name: "No Sub Permission Parent", identifier: "no-sub-perm-parent")
      EnabledModule.create!(project_id: parent.id, name: "ai_helper")
      Role.find(4).add_permission!(:view_ai_helper) # keep the parent accessible to rhill
      User.current = User.find(4)

      result = @provider.create_project(name: "Child No Permission", identifier: "child-no-perm", parent_id: parent.id)

      assert_equal({ error: "Permission denied: add_subprojects on project #{parent.id}" }, result)
    end

    should "reject a parent that is invisible or not accessible" do
      archived = Project.create!(name: "Archived Sub Parent", identifier: "archived-sub-parent", status: Project::STATUS_ARCHIVED)

      result = @provider.create_project(name: "Child Bad Parent", identifier: "child-bad-parent", parent_id: archived.id)

      assert_equal({ error: "Parent project not allowed: id = #{archived.id}" }, result)
    end

    should "reject is_public when the role given to non-admin creators lacks the permission" do
      Project.stubs(:default_member_role).returns(limited_role)
      User.current = User.find(2)

      result = @provider.create_project(name: "Publicity Test", identifier: "publicity-test", is_public: true)

      assert_equal(
        { error: "Permission denied: select_project_publicity (the role given to non-admin creators lacks it)" },
        result
      )
    end

    should "reject inherit_members when the role given to non-admin creators lacks the permission" do
      Project.stubs(:default_member_role).returns(limited_role)
      User.current = User.find(2)

      result = @provider.create_project(name: "Inherit Test", identifier: "inherit-test", inherit_members: true)

      assert_equal({ error: "Permission denied: manage_members (inherit_members)" }, result)
    end

    should "reject before creation when no role is configured for non-admin creators" do
      Project.stubs(:default_member_role).returns(nil)
      User.current = User.find(2)

      assert_no_difference "Project.count" do
        result = @provider.create_project(name: "No Role Test", identifier: "no-role-test")
        assert_equal({ error: "No role is configured for non-admin project creators" }, result)
      end
    end

    should "reject a duplicated identifier with the validation message" do
      result = @provider.create_project(name: "Duplicate Test", identifier: "ecookbook")

      assert_equal({ error: "Failed to create project: Identifier has already been taken" }, result)
    end

    should "roll back the project when the default member cannot be saved" do
      User.current = User.find(2)
      failing_member = mock("member")
      failing_member.stubs(:save!).raises(ActiveRecord::RecordInvalid)
      Project.any_instance.stubs(:add_default_member).returns(failing_member)

      assert_raises(ActiveRecord::RecordInvalid) do
        @provider.create_project(name: "Rollback Test", identifier: "rollback-test")
      end

      assert_nil Project.find_by(identifier: "rollback-test")
    end

    should "require confirmation in the tool description" do
      schema = RedmineAiHelper::Tools::ProjectWriteTools.function_schemas.to_openai_format
      description = schema.find { |f| f[:function][:name].end_with?("__create_project") }[:function][:description]

      assert_match(/Always confirm with the user before/i, description)
      assert_match(/identifier/i, description)
    end
  end

  context "update_project" do
    should "change only the given attributes and return the Project shape" do
      before = project_to_hash_for_assert(@project)

      result = @provider.update_project(project_id: @project.id, name: "Renamed eCookbook", description: "New description")

      assert_equal "Renamed eCookbook", result[:name]
      assert_equal "New description", result[:description]
      reloaded = @project.reload
      assert_equal before.merge(name: "Renamed eCookbook"), project_to_hash_for_assert(reloaded)
      # The full Project shape of contracts/project_tools.md
      %i[id name identifier description homepage is_public parent inherit_members status
         custom_fields enabled_modules trackers url_for_project].each do |key|
        assert result.key?(key), "expected key #{key}"
      end
      assert_equal @project.identifier, result[:identifier]
      assert_nil result[:parent]
      assert_equal @project.enabled_module_names, result[:enabled_modules]
      assert_equal(@project.trackers.map(&:id), result[:trackers].map { |t| t[:id] })
      assert_match(%r{^/projects/}, result[:url_for_project])
    end

    should "clear description and homepage with an empty string" do
      @project.update!(description: "Old text", homepage: "https://example.com")

      result = @provider.update_project(project_id: @project.id, description: "", homepage: "")

      assert result[:description].blank?
      assert result[:homepage].blank?
      assert @project.reload.description.blank?
      assert @project.reload.homepage.blank?
    end

    should "change the parent project" do
      parent = Project.create!(name: "New Parent", identifier: "new-parent")
      EnabledModule.create!(project_id: parent.id, name: "ai_helper")

      result = @provider.update_project(project_id: @project.id, parent_id: parent.id)

      assert_equal({ id: parent.id, name: parent.name }, result[:parent])
      assert_equal parent.id, @project.reload.parent_id
    end

    should "clear the parent with clear_parent" do
      # Project 3 is a subproject of project 1
      EnabledModule.create!(project_id: 3, name: "ai_helper")
      result = @provider.update_project(project_id: 3, clear_parent: true)

      assert_nil result[:parent]
      assert_nil Project.find(3).reload.parent_id
    end

    should "save nothing and return the current state when no attribute is given" do
      before = project_to_hash_for_assert(@project)

      result = @provider.update_project(project_id: @project.id)

      assert_equal @project.id, result[:id]
      assert_equal before, project_to_hash_for_assert(@project.reload)
    end

    should "reject a project without edit_project permission and change nothing" do
      Role.find(1).remove_permission!(:edit_project)
      Role.find(2).remove_permission!(:edit_project)
      User.current = User.find(2) # jsmith: Manager in project 1
      before = project_to_hash_for_assert(@project)

      result = @provider.update_project(project_id: @project.id, name: "Hacked Name")

      assert_equal({ error: "Permission denied: edit_project on project #{@project.id}" }, result)
      assert_equal before, project_to_hash_for_assert(@project.reload)
    end

    should "reject parent_id together with clear_parent" do
      EnabledModule.create!(project_id: 3, name: "ai_helper")
      result = @provider.update_project(project_id: 3, parent_id: 2, clear_parent: true)

      assert result[:error].present?
      assert_equal 1, Project.find(3).reload.parent_id
    end

    should "reject a parent that is invisible, not accessible, or not in allowed_parents" do
      # Invisible: an archived project is not visible even to the admin
      archived = Project.create!(name: "Archived Parent", identifier: "archived-parent", status: Project::STATUS_ARCHIVED)

      result = @provider.update_project(project_id: @project.id, parent_id: archived.id)

      assert_equal({ error: "Parent project not allowed: id = #{archived.id}" }, result)

      # Not in allowed_parents: Redmine's validate_parent would only say "invalid"
      result = @provider.update_project(project_id: @project.id, parent_id: 999)

      assert_equal({ error: "Parent project not allowed: id = 999" }, result)
    end

    should "reject is_public when the user may not set publicity" do
      Role.find(1).remove_permission!(:select_project_publicity)
      Role.find(2).remove_permission!(:select_project_publicity)
      User.current = User.find(2)
      before = @project.is_public

      result = @provider.update_project(project_id: @project.id, is_public: !before)

      assert_equal({ error: "Permission denied: select_project_publicity" }, result)
      assert_equal before, @project.reload.is_public
    end

    should "reject inherit_members when the user may not manage members" do
      Role.find(1).remove_permission!(:manage_members)
      Role.find(2).remove_permission!(:manage_members)
      User.current = User.find(2)

      result = @provider.update_project(project_id: @project.id, inherit_members: true)

      assert_equal({ error: "Permission denied: manage_members (inherit_members)" }, result)
      assert_equal false, @project.reload.inherit_members
    end

    should "reject a custom field the user cannot edit" do
      custom_field = ProjectCustomField.create!(name: "Secret Field", field_format: "string", is_for_all: true, visible: false)
      User.current = User.find(2) # jsmith: the field is not visible to him

      result = @provider.update_project(project_id: @project.id, custom_fields: [ { field_id: custom_field.id, value: "X" } ])

      assert_match(/not editable/, result[:error])
      assert_nil @project.reload.custom_value_for(custom_field)
      custom_field.destroy
    end

    should "drop custom field entries without field_id with a warning" do
      custom_field = ProjectCustomField.create!(name: "Droppable Field", field_format: "string", is_for_all: true)
      logger = mock("logger")
      logger.expects(:warn).at_least_once.with { |msg| msg.to_s.include?("field_id") }
      @provider.stubs(:ai_helper_logger).returns(logger)

      result = @provider.update_project(project_id: @project.id, custom_fields: [ { value: "orphan" }, { field_id: custom_field.id, value: "Set" } ])

      assert_nil result[:error]
      assert_equal "Set", @project.reload.custom_value_for(custom_field)&.value
      custom_field.destroy
    end

    should "not accept an identifier parameter at all" do
      schema = RedmineAiHelper::Tools::ProjectWriteTools.function_schemas.to_openai_format
      properties = schema.find { |f| f[:function][:name].end_with?("__update_project") }[:function][:parameters][:properties]

      assert_not properties.key?("identifier")
    end

    should "reject a closed project" do
      closed = Project.create!(name: "Closed Update Test", identifier: "closed-update-test", status: Project::STATUS_CLOSED)
      AiHelperSetting.stubs(:all_projects_scope?).returns(true)

      result = @provider.update_project(project_id: closed.id, name: "New Name")

      assert_equal({ error: "Project is closed: id = #{closed.id}" }, result)
      assert_equal "Closed Update Test", closed.reload.name
    end

    should "reject a project that is not accessible" do
      other = Project.create!(name: "No Module Update Test", identifier: "no-module-update-test")
      AiHelperSetting.stubs(:all_projects_scope?).returns(false)

      result = @provider.update_project(project_id: other.id, name: "New Name")

      assert_equal({ error: "Project is not accessible: id = #{other.id}" }, result)
    end

    should "report Redmine validation errors and change nothing" do
      result = @provider.update_project(project_id: @project.id, name: "")

      assert_match(/Failed to update project: Name cannot be blank/, result[:error])
      assert_equal "eCookbook", @project.reload.name
    end

    should "require confirmation before making the project public in the tool description" do
      schema = RedmineAiHelper::Tools::ProjectWriteTools.function_schemas.to_openai_format
      description = schema.find { |f| f[:function][:name].end_with?("__update_project") }[:function][:description]

      assert_match(/Always confirm with the user before/i, description)
    end
  end

  context "no destructive tools" do
    should "not define a delete, destroy, or archive tool" do
      assert_no_destructive_tool_names(RedmineAiHelper::Tools::ProjectWriteTools)
    end

    should "not call a destructive method in the tool code" do
      assert_destructive_calls_only(RedmineAiHelper::Tools::ProjectWriteTools, allowed: [])
    end
  end
end
