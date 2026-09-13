require File.expand_path("../../../test_helper", __FILE__)

class RepositoryToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :repositories, :changesets, :changes,
           :enabled_modules, :roles, :members, :member_roles

  def setup
    @provider = RedmineAiHelper::Tools::RepositoryTools.new
    repo_dir = Rails.root.join("plugins/redmine_ai_helper/tmp/redmine_ai_helper_test_repo.git").to_s
    @project = Project.find(1)
    @repository = @project.create_repository(
      type: "Repository::Git",
      url: repo_dir,
      identifier: "test"
    )
    @repository.fetch_changesets
    @repository.save!
    # The repository tools require the ai_helper module and the view_ai_helper
    # permission on the repository's project (project 1, via jsmith's role 1),
    # on top of Redmine's own repository permissions.
    @previous_user = User.current
    User.current = User.find(2)
    EnabledModule.create!(project_id: @project.id, name: "ai_helper")
    Role.find(1).add_permission!(:view_ai_helper)
  end

  def teardown
    User.current = @previous_user
  end

  def test_repository_info_success
    response = @provider.repository_info(repository_id: @repository.id)

    assert_equal @repository.id, response[:id]
    assert_equal "Git", response[:type]
    assert_equal "test", response[:name]
  end

  def test_repository_info_not_found
    assert_raises(RuntimeError, "Repository not found") do
      @provider.repository_info(repository_id: 999)
    end
  end

  def test_get_file_info_success
    response = @provider.get_file_info(repository_id: @repository.id, path: "README.md", revision: "main")

    assert_equal 119, response[:size]
    assert_equal "file", response[:type]
    assert response[:is_text]
  end

  def test_get_file_info_not_found
    assert_raises(RuntimeError, "Repository not found") do
      @provider.get_file_info(repository_id: 999, path: "README.md", revision: "main")
    end
  end

  def test_read_file_success
    response = @provider.read_file(repository_id: @repository.id, path: "README.md", revision: "main")

    assert_includes response[:content], "some text"
  end

  def test_read_file_not_found
    assert_raises(RuntimeError, "Repository not found") do
      @provider.read_file(repository_id: 999, path: "README.md", revision: "main")
    end
  end

  def test_read_file_not_text
    assert_raises(RuntimeError, "File is not text") do
      @provider.read_file(repository_id: @repository.id, path: "test_dir/hello.zip", revision: "main")
    end
  end

  def test_get_revision_info_success
    changeset = @repository.changesets.second
    revision = changeset.revision
    response = @provider.get_revision_info(repository_id: @repository.id, revision: revision)

    assert_equal revision, response[:revision]
    assert_equal changeset.committed_on, response[:committed_on]
    assert_equal changeset.comments, response[:comments]
  end

  def test_get_revision_info_not_found
    assert_raises(RuntimeError, "Repository not found") do
      @provider.get_revision_info(repository_id: 999, revision: "invalid_revision")
    end

    assert_raises(RuntimeError, "Revision not found") do
      @provider.get_revision_info(repository_id: @repository.id, revision: "invalid_revision")
    end
  end

  def test_read_diff_success
    changeset = @repository.changesets.second
    revision = changeset.revision
    response = @provider.read_diff(repository_id: @repository.id, revision: revision)

    assert_includes response[:diff], "diff --git"
  end

  def test_repository_info_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.repository_info(repository_id: @repository.id)
    end
  end

  def test_read_file_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.read_file(repository_id: @repository.id, path: "README.md", revision: "main")
    end
  end

  def test_get_file_info_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.get_file_info(repository_id: @repository.id, path: "README.md", revision: "main")
    end
  end

  def test_get_revision_info_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.get_revision_info(repository_id: @repository.id, revision: @repository.changesets.second.revision)
    end
  end

  def test_read_diff_denied_when_module_disabled_and_scope_off
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(false)

    assert_raises(RuntimeError) do
      @provider.read_diff(repository_id: @repository.id, revision: @repository.changesets.second.revision)
    end
  end

  def test_read_file_allowed_when_module_disabled_and_scope_on
    disable_ai_helper_module
    AiHelperSetting.stubs(:all_projects_scope?).returns(true)

    response = @provider.read_file(repository_id: @repository.id, path: "README.md", revision: "main")

    assert_includes response[:content], "some text"
  end

  def test_read_file_denied_without_browse_repository_permission
    Role.find(1).remove_permission!(:browse_repository)

    assert_raises(RuntimeError) do
      @provider.read_file(repository_id: @repository.id, path: "README.md", revision: "main")
    end
  end

  def test_get_file_info_denied_without_browse_repository_permission
    Role.find(1).remove_permission!(:browse_repository)

    assert_raises(RuntimeError) do
      @provider.get_file_info(repository_id: @repository.id, path: "README.md", revision: "main")
    end
  end

  def test_repository_info_denied_without_browse_repository_permission
    Role.find(1).remove_permission!(:browse_repository)

    assert_raises(RuntimeError) do
      @provider.repository_info(repository_id: @repository.id)
    end
  end

  def test_read_diff_denied_without_browse_repository_permission
    Role.find(1).remove_permission!(:browse_repository)

    assert_raises(RuntimeError) do
      @provider.read_diff(repository_id: @repository.id, revision: @repository.changesets.second.revision)
    end
  end

  def test_get_revision_info_denied_without_view_changesets_permission
    Role.find(1).remove_permission!(:view_changesets)

    assert_raises(RuntimeError) do
      @provider.get_revision_info(repository_id: @repository.id, revision: @repository.changesets.second.revision)
    end
  end

  def test_read_file_denied_for_project_invisible_to_the_user
    User.current = User.anonymous
    @project.update!(is_public: false)

    assert_raises(RuntimeError) do
      @provider.read_file(repository_id: @repository.id, path: "README.md", revision: "main")
    end
  end

  private

  def disable_ai_helper_module
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all
    @project.reload
  end
end
