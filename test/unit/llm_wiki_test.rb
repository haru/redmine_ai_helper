require File.expand_path("../../test_helper", __FILE__)

class LlmWikiTest < ActiveSupport::TestCase
  fixtures :projects, :users, :wikis, :wiki_pages, :wiki_contents, :roles, :members, :member_roles

  setup do
    @project = projects(:projects_001)
    @wiki_page = wiki_pages(:wiki_pages_001)
    @llm = RedmineAiHelper::Llm.new
    User.current = users(:users_002)
  end

  teardown do
    User.current = nil
  end

  test "generate_wiki_completion should return string" do
    RedmineAiHelper::Agents::WikiAgent.any_instance.stubs(:generate_wiki_completion).returns("test completion")

    result = @llm.generate_wiki_completion(
      text: "This project",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page
    )

    assert_kind_of String, result
    assert_equal "test completion", result
  end

  test "generate_wiki_completion should handle agent errors" do
    RedmineAiHelper::Agents::WikiAgent.any_instance.stubs(:generate_wiki_completion).raises(StandardError.new("Agent error"))

    result = @llm.generate_wiki_completion(
      text: "Error test",
      cursor_position: 10,
      project: @project,
      wiki_page: @wiki_page
    )

    assert_equal "", result
  end

  test "generate_wiki_completion should create WikiAgent with correct options" do
    mock_agent = mock("wiki_agent")
    mock_agent.stubs(:llm_provider=)
    mock_agent.stubs(:generate_wiki_completion).returns("completion")

    RedmineAiHelper::Agents::WikiAgent.expects(:new).with(
      has_entries(project: @project)
    ).returns(mock_agent)

    @llm.generate_wiki_completion(
      text: "test",
      project: @project,
      wiki_page: @wiki_page
    )
  end

  test "generate_wiki_completion should pass correct parameters to agent" do
    mock_agent = mock("wiki_agent")
    mock_agent.stubs(:llm_provider=)

    mock_agent.expects(:generate_wiki_completion).with(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page,
      is_section_edit: false
    ).returns("completion")

    RedmineAiHelper::Agents::WikiAgent.stubs(:new).returns(mock_agent)

    @llm.generate_wiki_completion(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page
    )
  end

  test "generate_wiki_completion should handle nil parameters" do
    RedmineAiHelper::Agents::WikiAgent.any_instance.stubs(:generate_wiki_completion).returns("completion")

    result = @llm.generate_wiki_completion(
      text: "test",
      cursor_position: nil,
      project: nil,
      wiki_page: nil
    )

    assert_kind_of String, result
  end

  test "generate_wiki_completion should handle section editing parameters" do
    mock_agent = mock("wiki_agent")
    mock_agent.stubs(:llm_provider=)

    mock_agent.expects(:generate_wiki_completion).with(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page,
      is_section_edit: true
    ).returns("section completion")

    RedmineAiHelper::Agents::WikiAgent.stubs(:new).returns(mock_agent)

    result = @llm.generate_wiki_completion(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page,
      is_section_edit: true
    )

    assert_equal "section completion", result
  end

  # Completion requests must run with a bounded timeout and no retries so a
  # slow backend cannot occupy an application worker for minutes (ADR-018).
  test "generate_wiki_completion should build request options from the configured timeout" do
    RedmineAiHelper::Util::ConfigFile.stubs(:autocompletion_settings).returns({ timeout: 12 })
    completion_provider = mock("completion_provider")
    RedmineAiHelper::LlmProvider.expects(:get_llm_provider)
      .with(request_options: { request_timeout: 12, max_retries: 0 })
      .returns(completion_provider)

    mock_agent = mock("WikiAgent")
    mock_agent.expects(:llm_provider=).with(completion_provider)
    mock_agent.expects(:generate_wiki_completion).returns("completion")
    RedmineAiHelper::Agents::WikiAgent.expects(:new).returns(mock_agent)

    result = @llm.generate_wiki_completion(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page
    )

    assert_equal "completion", result
  end

  test "generate_wiki_completion should use the default timeout when unset" do
    RedmineAiHelper::Util::ConfigFile.stubs(:autocompletion_settings).returns({ timeout: 30 })
    completion_provider = mock("completion_provider")
    RedmineAiHelper::LlmProvider.expects(:get_llm_provider)
      .with(request_options: { request_timeout: 30, max_retries: 0 })
      .returns(completion_provider)

    mock_agent = mock("WikiAgent")
    mock_agent.expects(:llm_provider=).with(completion_provider)
    mock_agent.expects(:generate_wiki_completion).returns("completion")
    RedmineAiHelper::Agents::WikiAgent.expects(:new).returns(mock_agent)

    @llm.generate_wiki_completion(
      text: "test content",
      cursor_position: 12,
      project: @project,
      wiki_page: @wiki_page
    )
  end
end
