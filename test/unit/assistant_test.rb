require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/assistant"

class RedmineAiHelper::AssistantTest < ActiveSupport::TestCase
  setup do
    @mock_chat = mock("RubyLLM::Chat")
    @assistant = RedmineAiHelper::Assistant.new(
      chat: @mock_chat,
      instructions: "Test instructions",
      tools: [],
    )
  end

  context "Assistant" do
    should "store chat instance" do
      assert_equal @mock_chat, @assistant.chat
    end

    should "have llm_provider accessor" do
      @assistant.llm_provider = "test_provider"
      assert_equal "test_provider", @assistant.llm_provider
    end

    context "add_message" do
      should "delegate to chat" do
        @mock_chat.expects(:add_message).with(role: :user, content: "Hello")
        @assistant.add_message(role: "user", content: "Hello")
      end

      should "convert role to symbol" do
        @mock_chat.expects(:add_message).with(role: :assistant, content: "Hi")
        @assistant.add_message(role: "assistant", content: "Hi")
      end
    end

    context "run" do
      should "ask the chat with the last user message and return response array" do
        mock_message = mock("Message")
        mock_message.stubs(:role).returns(:user)
        mock_message.stubs(:content).returns("test question")

        mock_response = mock("Response")
        mock_response.stubs(:content).returns("test answer")

        @mock_chat.stubs(:messages).returns([mock_message])
        @mock_chat.expects(:ask).with("test question").returns(mock_response)

        result = @assistant.run(auto_tool_execution: true)
        assert_equal [mock_response], result
      end
    end

    context "clear_messages!" do
      should "reset the chat" do
        @mock_chat.expects(:reset)
        @assistant.clear_messages!
      end
    end

    context "messages" do
      should "delegate to chat" do
        mock_messages = [mock("Message1"), mock("Message2")]
        @mock_chat.expects(:messages).returns(mock_messages)
        assert_equal mock_messages, @assistant.messages
      end
    end

    context "instructions=" do
      should "store new instructions" do
        @assistant.instructions = "New instructions"
        assert_equal "New instructions", @assistant.instance_variable_get(:@instructions)
      end
    end
  end
end
