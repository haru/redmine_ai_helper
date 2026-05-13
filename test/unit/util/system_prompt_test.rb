require File.expand_path("../../../test_helper", __FILE__)

class SystemPromptTest < ActiveSupport::TestCase
  fixtures :users, :projects, :issues, :repositories, :wiki_pages

  def setup
    @project = projects(:projects_001)
    @issue = issues(:issues_001)
    @wiki_page = wiki_pages(:wiki_pages_001)
    @repository = repositories(:repositories_001)
    @user = users(:users_001)
    User.current = @user
  end

  def test_prompt_with_project_page
    options = { controller_name: "projects", action_name: "show", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the information page for the project '#{@project.name}'/, prompt)
  end

  def test_prompt_with_issue_page
    options = { controller_name: "issues", action_name: "show", content_id: @issue.id, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the detail page for issue ##{@issue.id}/, prompt)
  end

  def test_prompt_with_issue_index_page
    options = { controller_name: "issues", action_name: "index", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the issue list page./, prompt)
  end

  def test_prompt_with_issue_new_page
    options = { controller_name: "issues", action_name: "new", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the new page for the issue./, prompt)
  end

  def test_prompt_with_wiki_page
    options = { controller_name: "wiki", action_name: "show", content_id: @wiki_page.id, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the Wiki page titled '#{@wiki_page.title}'/, prompt)
  end

  def test_prompt_with_repository_page
    options = { controller_name: "repositories", action_name: "show", content_id: @repository.id, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the information page for the repository '#{@repository.name}'/, prompt)
  end

  def test_prompt_with_repository_entry_page
    options = { controller_name: "repositories", action_name: "entry", content_id: @repository.id, additional_info: { "path" => "path/to/file", "rev" => "123" }, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/The displayed file path is path\/to\/file. The revision is 123. The repository is '#{@repository.name}/, prompt)
  end

  def test_prompt_with_repository_diff_page
    options = { controller_name: "repositories", action_name: "diff", content_id: @repository.id, additional_info: { "rev" => "123", "rev_to" => "456", "path" => "path/to/file" }, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/diff page for the repository '#{@repository.name}/, prompt)
  end

  def test_prompt_with_repository_revision_page
    options = { controller_name: "repositories", action_name: "revision", content_id: @repository.id, additional_info: { "rev" => "123" }, project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the revision information page for the repository '#{@repository.name}'/, prompt)
  end

  def test_prompt_with_repository_other_page
    options = { controller_name: "repositories", action_name: "other", project: @project, content_id: @repository.id }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the information page for the repository./, prompt)
  end

  def test_prompt_with_board_page
    options = { controller_name: "boards", action_name: "show", content_id: 1, project: @project }
    board = Board.find(1)
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/forum '#{board.name}'. The forum ID is #{board.id}/, prompt)
  end

  def test_prompt_with_board_index_page
    options = { controller_name: "boards", action_name: "index", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the forum list page./, prompt)
  end

  def test_prompot_with_board_index_page_with_board
    options = { controller_name: "boards", action_name: "index", project: @project, content_id: 1 }
    board = Board.find(1)
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/forum '#{board.name}'. The forum ID is #{board.id}/, prompt)
  end

  def test_prompt_with_board_other_page
    options = { controller_name: "boards", action_name: "other", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the page for the forum./, prompt)
  end

  def test_prompt_with_message_page
    options = { controller_name: "messages", action_name: "show", project: @project, content_id: 1 }
    message = Message.find(1)
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the page for the message '#{message.subject}'. The message ID is #{message.id}/, prompt)
  end

  def test_prompt_with_message_other_page
    options = { controller_name: "messages", action_name: "other", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the page for the message./, prompt)
  end

  def test_site_info_json
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new
    json = system_prompt.send(:site_info_json, project: @project)

    assert_match(/"title": "#{Setting.app_title}"/, json)
    assert_match(/"current_project": {/, json)
    assert_match(/"name": "#{@project.name}"/, json)
  end

  def test_prompt_with_version_page
    options = { controller_name: "versions", action_name: "show", project: @project, content_id: 1 }
    version = Version.find(1)
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/version '#{version.name}'. The version ID is #{version.id}/, prompt)
  end

  def test_prompt_with_version_other_page
    options = { controller_name: "versions", action_name: "other", project: @project }
    system_prompt = RedmineAiHelper::Util::SystemPrompt.new(options)
    prompt = system_prompt.prompt

    assert_match(/This is the page for the version./, prompt)
  end
end
