require File.expand_path("../../test_helper", __FILE__)

class AssistantProviderTest < ActiveSupport::TestCase
  def setup
    @mock_llm_provider = mock("llm_provider")
    @instructions = "Test instructions"
    @tool_classes = []
  end

  def test_get_assistant_creates_chat_via_llm_provider
    mock_chat = mock("RubyLLM::Chat")
    @mock_llm_provider.expects(:create_chat).with(
      instructions: @instructions,
      tools: @tool_classes,
    ).returns(mock_chat)

    assistant = RedmineAiHelper::AssistantProvider.get_assistant(
      llm_provider: @mock_llm_provider,
      instructions: @instructions,
      tools: @tool_classes,
    )

    assert_instance_of RedmineAiHelper::Assistant, assistant
    assert_equal mock_chat, assistant.chat
  end

  def test_get_assistant_with_default_empty_tools
    mock_chat = mock("RubyLLM::Chat")
    @mock_llm_provider.expects(:create_chat).with(
      instructions: @instructions,
      tools: [],
    ).returns(mock_chat)

    assistant = RedmineAiHelper::AssistantProvider.get_assistant(
      llm_provider: @mock_llm_provider,
      instructions: @instructions,
    )

    assert_instance_of RedmineAiHelper::Assistant, assistant
  end

  def test_get_assistant_with_tool_classes
    tool_class1 = mock("ToolClass1")
    tool_class2 = mock("ToolClass2")
    tools = [tool_class1, tool_class2]
    mock_chat = mock("RubyLLM::Chat")

    @mock_llm_provider.expects(:create_chat).with(
      instructions: @instructions,
      tools: tools,
    ).returns(mock_chat)

    assistant = RedmineAiHelper::AssistantProvider.get_assistant(
      llm_provider: @mock_llm_provider,
      instructions: @instructions,
      tools: tools,
    )

    assert_instance_of RedmineAiHelper::Assistant, assistant
  end
end
