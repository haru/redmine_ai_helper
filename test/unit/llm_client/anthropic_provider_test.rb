require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/anthropic_provider"

class RedmineAiHelper::LlmClient::AnthropicProviderTest < ActiveSupport::TestCase
  context "AnthropicProvider" do
    setup do
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile

      @anthropic_profile = AiHelperModelProfile.create!(
        name: "Test Anthropic Profile",
        llm_type: "Anthropic",
        llm_model: "claude-sonnet-4-5-20250929",
        access_key: "test_anthropic_key",
      )
      @setting.model_profile = @anthropic_profile
      @setting.save!

      @provider = RedmineAiHelper::LlmClient::AnthropicProvider.new
    end

    teardown do
      @setting.model_profile = @original_profile
      @setting.save!
      @anthropic_profile.destroy
    end

    should "configure RubyLLM with Anthropic API key" do
      @provider.configure_ruby_llm
      assert_equal "test_anthropic_key", RubyLLM.config.anthropic_api_key
    end

    should "raise error when model profile is missing" do
      @setting.model_profile = nil
      @setting.save!
      assert_raises(RuntimeError, "Model Profile not found") do
        @provider.configure_ruby_llm
      end
    end

    should "create chat via base class" do
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).with("Test prompt")
      mock_chat.expects(:with_temperature).with(@anthropic_profile.temperature)
      RubyLLM.expects(:chat).with(model: @anthropic_profile.llm_model).returns(mock_chat)

      chat = @provider.create_chat(instructions: "Test prompt")
      assert_equal mock_chat, chat
    end
  end
end
