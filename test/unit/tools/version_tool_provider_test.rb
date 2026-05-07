require File.expand_path("../../../test_helper", __FILE__)

class VersionToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :boards, :messages

  def setup
    @provider = RedmineAiHelper::Tools::VersionTools.new
    @project = Project.find(1)
    @version = @project.versions.first
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
end
