require File.expand_path("../../../test_helper", __FILE__)

class RepositoryToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :repositories, :changesets, :changes

  def setup
    @provider = RedmineAiHelper::Tools::RepositoryTools.new
    repo_dir = Rails.root.join("plugins/redmine_ai_helper/tmp", "redmine_ai_helper_test_repo.git").to_s
    @project = Project.find(1)
    @repository = @project.create_repository(
      type: "Repository::Git",
      url: repo_dir,
      identifier: "test"
    )
    @repository.fetch_changesets
    @repository.save!
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
    assert response[:content].include?("some text")
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
    assert response[:diff].include?("diff --git")
  end
end
