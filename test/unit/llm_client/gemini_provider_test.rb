require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/gemini_provider"

class RedmineAiHelper::LlmClient::GeminiProviderTest < ActiveSupport::TestCase
  context "GeminiProvider" do
    setup do
      @provider = RedmineAiHelper::LlmClient::GeminiProvider.new
    end

    should "generate a valid client" do
      Langchain::LLM::GoogleGemini.stubs(:new).returns(mock("GeminiClient"))
      client = @provider.generate_client
      assert_not_nil client
    end

    should "raise an error if client generation fails" do
      Langchain::LLM::GoogleGemini.stubs(:new).returns(nil)
      assert_raises(RuntimeError, "Gemini LLM Create Error") do
        @provider.generate_client
      end
    end

    should "create valid chat parameters" do
      system_prompt = { content: "This is a system prompt" }
      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
      ]
      chat_params = @provider.create_chat_param(system_prompt, messages)

      assert_equal 2, chat_params[:contents].size
      assert_equal "user", chat_params[:contents][0][:role]
      assert_equal "Hello", chat_params[:contents][0][:parts][0][:text]
      assert_equal "model", chat_params[:contents][1][:role]
      assert_equal "Hi there!", chat_params[:contents][1][:parts][0][:text]
      assert_equal "This is a system prompt", chat_params[:system_instruction][:parts][0][:text]
    end

    should "reset assistant messages correctly" do
      assistant = mock("Assistant")
      assistant.expects(:clear_messages!).once
      assistant.expects(:instructions=).with("System instructions").once
      assistant.expects(:add_message).with(role: "user", content: "Hello").once
      assistant.expects(:add_message).with(role: "model", content: "Hi there!").once

      system_prompt = "System instructions"
      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there!" },
      ]

      @provider.reset_assistant_messages(
        assistant: assistant,
        system_prompt: system_prompt,
        messages: messages,
      )
    end
  end
end
