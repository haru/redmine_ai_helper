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

  private

  def disable_ai_helper_module
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all
    @project.reload
  end
end
