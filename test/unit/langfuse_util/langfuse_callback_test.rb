require File.expand_path("../../../test_helper", __FILE__)

# Tests for RubyLLM callback-based Langfuse generation tracking.
# This replaces the old provider-specific Langfuse wrapper tests
# (open_ai_test.rb, anthropic_test.rb, gemini_test.rb, azure_open_ai_test.rb).
class LangfuseCallbackTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @project = Project.find(1)

    # Stub LLM provider
    @mock_provider = mock("llm_provider")
    @mock_provider.stubs(:model_name).returns("gpt-4")
    @mock_provider.stubs(:temperature).returns(0.7)
    @mock_provider.stubs(:max_tokens).returns(4096)
    @mock_provider.stubs(:create_chat).returns(mock_assistant_chat)
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_provider)
    RedmineAiHelper::LlmProvider.stubs(:type).returns("OpenAI")
  end

  context "setup_langfuse_callbacks" do
    should "create generation with input messages and usage data on assistant message" do
      mock_langfuse = create_mock_langfuse
      mock_span = mock_langfuse.current_span
      mock_generation = mock("generation")

      # Simulate messages in the chat instance (including the response as last element)
      user_msg = create_mock_message(role: :user, content: "What can you do?")
      assistant_msg = create_mock_message(role: :assistant, content: "Hello, how can I help?", input_tokens: 10, output_tokens: 20)

      # Expect generation to be created with actual input messages (excluding the response)
      mock_span.expects(:create_generation).with(
        name: "chat",
        messages: [{ role: "user", content: "What can you do?" }],
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 4096,
      ).returns(mock_generation)

      mock_generation.expects(:finish).with(
        output: "Hello, how can I help?",
        usage: {
          prompt_tokens: 10,
          completion_tokens: 20,
          total_tokens: 30,
        },
      )

      agent = create_agent_with_langfuse(mock_langfuse)
      chat_instance = CallbackCapture.new([user_msg, assistant_msg])
      agent.send(:setup_langfuse_callbacks, chat_instance)

      # Simulate on_end_message callback with assistant message
      chat_instance.fire_end_message(assistant_msg)
    end

    should "use tool_calls as output when content is nil" do
      mock_langfuse = create_mock_langfuse
      mock_span = mock_langfuse.current_span
      mock_generation = mock("generation")

      user_msg = create_mock_message(role: :user, content: "Get issue #1")
      tool_call = mock("tool_call")
      tool_call.stubs(:to_h).returns({ id: "call_1", name: "get_issue", arguments: { issue_id: 1 } })
      # RubyLLM tool_calls is a Hash { call_id => ToolCall }
      assistant_msg = create_mock_message(
        role: :assistant, content: nil, input_tokens: 15, output_tokens: 10,
        tool_calls: { "call_1" => tool_call },
      )

      mock_span.expects(:create_generation).with(
        name: "chat",
        messages: [{ role: "user", content: "Get issue #1" }],
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 4096,
      ).returns(mock_generation)

      mock_generation.expects(:finish).with(
        output: [{ id: "call_1", name: "get_issue", arguments: { issue_id: 1 } }].to_json,
        usage: {
          prompt_tokens: 15,
          completion_tokens: 10,
          total_tokens: 25,
        },
      )

      agent = create_agent_with_langfuse(mock_langfuse)
      chat_instance = CallbackCapture.new([user_msg, assistant_msg])
      agent.send(:setup_langfuse_callbacks, chat_instance)

      chat_instance.fire_end_message(assistant_msg)
    end

    should "skip generation for non-assistant messages" do
      mock_langfuse = create_mock_langfuse
      mock_span = mock_langfuse.current_span

      # Generation should NOT be created for tool messages
      mock_span.expects(:create_generation).never

      agent = create_agent_with_langfuse(mock_langfuse)
      chat_instance = CallbackCapture.new
      agent.send(:setup_langfuse_callbacks, chat_instance)

      # Simulate on_end_message callback with tool message
      message = create_mock_message(role: :tool, content: "tool result")
      chat_instance.fire_end_message(message)
    end

    should "not register callback when langfuse is nil" do
      agent = create_agent_with_langfuse(nil)
      chat_instance = CallbackCapture.new
      agent.send(:setup_langfuse_callbacks, chat_instance)

      # Callback should not be set
      assert_nil chat_instance.end_message_callback
    end

    should "skip generation when no current span" do
      mock_langfuse = create_mock_langfuse
      mock_langfuse.stubs(:current_span).returns(nil)

      agent = create_agent_with_langfuse(mock_langfuse)
      chat_instance = CallbackCapture.new
      agent.send(:setup_langfuse_callbacks, chat_instance)

      # Simulate on_end_message callback - should not raise
      message = create_mock_message(role: :assistant, content: "response")
      assert_nothing_raised do
        chat_instance.fire_end_message(message)
      end
    end

    should "handle message without token info" do
      mock_langfuse = create_mock_langfuse
      mock_span = mock_langfuse.current_span
      mock_generation = mock("generation")

      user_msg = create_mock_message(role: :user, content: "hello")
      assistant_msg = create_mock_message(role: :assistant, content: "response without tokens", input_tokens: nil, output_tokens: nil)

      mock_span.expects(:create_generation).returns(mock_generation)
      mock_generation.expects(:finish).with(
        output: "response without tokens",
        usage: {},
      )

      agent = create_agent_with_langfuse(mock_langfuse)
      chat_instance = CallbackCapture.new([user_msg, assistant_msg])
      agent.send(:setup_langfuse_callbacks, chat_instance)

      chat_instance.fire_end_message(assistant_msg)
    end
  end

  private

  # Simple object that captures RubyLLM-style on_end_message callback
  class CallbackCapture
    attr_reader :end_message_callback, :messages

    def initialize(messages = [])
      @messages = messages
    end

    def on_end_message(&block)
      @end_message_callback = block
      self
    end

    def fire_end_message(message)
      @end_message_callback&.call(message)
    end
  end

  def create_mock_langfuse
    mock_span = mock("span")
    mock_span.stubs(:create_generation).returns(nil)

    mock_langfuse = mock("langfuse")
    mock_langfuse.stubs(:current_span).returns(mock_span)
    mock_langfuse.stubs(:create_span)
    mock_langfuse.stubs(:finish_current_span)
    mock_langfuse
  end

  def create_agent_with_langfuse(langfuse)
    RedmineAiHelper::BaseAgent.new(project: @project, langfuse: langfuse)
  end

  def create_mock_message(role:, content:, input_tokens: nil, output_tokens: nil, tool_calls: nil)
    msg = mock("message")
    msg.stubs(:role).returns(role)
    msg.stubs(:content).returns(content)
    msg.stubs(:input_tokens).returns(input_tokens)
    msg.stubs(:output_tokens).returns(output_tokens)
    msg.stubs(:tool_calls).returns(tool_calls)
    msg
  end

  def mock_assistant_chat
    chat = mock("chat")
    chat.stubs(:with_instructions).returns(chat)
    chat.stubs(:with_tools).returns(chat)
    chat.stubs(:with_temperature).returns(chat)
    chat.stubs(:on_end_message).returns(chat)
    chat.stubs(:messages).returns([])
    chat
  end
end
