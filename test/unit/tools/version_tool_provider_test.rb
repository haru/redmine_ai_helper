require File.expand_path("../../../test_helper", __FILE__)

class VersionToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :boards, :messages,
           :enabled_modules, :roles, :members, :member_roles

  def setup
    @provider = RedmineAiHelper::Tools::VersionTools.new
    @project = Project.find(1)
    @version = @project.versions.first
    # The version tools require the ai_helper module and the view_ai_helper permission
    # on the version's project (project 1, via jsmith's role 1).
    @previous_user = User.current
    User.current = User.find(2)
    EnabledModule.create!(project_id: @project.id, name: "ai_helper")
    Role.find(1).add_permission!(:view_ai_helper)
  end

  def teardown
    User.current = @previous_user
  end

  def test_list_versions_success
    response = @provider.list_versions(project_id: @project.id)

    assert_equal @project.versions.count, response.size
  end

  def test_list_versions_project_not_found
    assert_raises(RuntimeError, "Project not found") do
      @provider.list_versions(project_id: 999)
    end
  end

  def test_version_info_success
    response = @provider.version_info(version_ids: [ @version.id ])

    assert_equal @version.id, response.first[:id]
    assert_equal @version.name, response.first[:name]
  end

  def test_version_info_not_found
    assert_raises(RuntimeError, "Version not found") do
      @provider.version_info(version_ids: [ 999 ])
    end
  end

  def test_version_info_reads_all_projects_scope_setting_once
    AiHelperSetting.expects(:all_projects_scope?).at_most_once.returns(true)
    version_ids = @project.versions.limit(3).pluck(:id)
    assert_operator version_ids.size, :>, 1

    response = @provider.version_info(version_ids: version_ids)

    assert_equal version_ids.size, response.size
  end

  def test_list_versions_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.list_versions(project_id: @project.id)
    end
  end

  def test_version_info_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.version_info(version_ids: [ @version.id ])
    end
  end

  def test_list_versions_allowed_when_module_disabled_and_scope_on
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(true)

    response = @provider.list_versions(project_id: @project.id)

    assert_equal @project.versions.count, response.size
  end

  def test_capable_version_props_for_regular_user
    cf = VersionCustomField.create!(name: "Sprint goal", field_format: "string", visible: true, editable: true)
    response = @provider.capable_version_props(project_id: @project.id)

    assert_equal @project.id, response[:project_id]
    assert_equal %w[open locked closed], response[:statuses]
    assert_not_includes response[:allowed_sharings], "system"
    field = response[:custom_fields].find { |f| f[:id] == cf.id }
    assert_equal "Sprint goal", field[:name]
    %i[field_format is_required multiple possible_values default_value].each { |k| assert field.key?(k) }
  end

  def test_capable_version_props_for_admin_includes_system
    User.current = User.find(1)
    response = @provider.capable_version_props(project_id: @project.id)

    assert_includes response[:allowed_sharings], "system"
  end

  def test_capable_version_props_hides_invisible_custom_fields
    hidden = VersionCustomField.create!(name: "Hidden", field_format: "string", visible: false, editable: true, role_ids: [ 2 ])
    response = @provider.capable_version_props(project_id: @project.id)

    assert_not_includes response[:custom_fields].map { |f| f[:id] }, hidden.id
  end

  def test_capable_version_props_lists_possible_values_with_values_to_set
    list = VersionCustomField.create!(name: "Phase", field_format: "list", possible_values: %w[Alpha Beta], visible: true, editable: true)
    enum = VersionCustomField.create!(name: "Team", field_format: "enumeration", visible: true, editable: true)
    backend = enum.enumerations.create!(name: "Backend", active: true)
    text = VersionCustomField.create!(name: "Goal", field_format: "string", visible: true, editable: true)
    fields = @provider.capable_version_props(project_id: @project.id)[:custom_fields].index_by { |f| f[:id] }

    assert_equal [ { value: "Alpha", label: "Alpha" }, { value: "Beta", label: "Beta" } ], fields[list.id][:possible_values]
    assert_equal [ { value: backend.id.to_s, label: "Backend" } ], fields[enum.id][:possible_values]
    assert_equal [], fields[text.id][:possible_values]
  end

  def test_capable_version_props_errors
    assert_equal({ error: "project_id is required" }, @provider.capable_version_props(project_id: nil))
    assert_equal({ error: "Project not found. id = 999" }, @provider.capable_version_props(project_id: 999))
    assert_equal({ error: "Project is not accessible: id = 2" }, @provider.capable_version_props(project_id: 2))
  end

  private

  def disable_ai_helper_module
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all
    @project.reload
  end
end
