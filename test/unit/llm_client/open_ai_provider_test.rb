require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/open_ai_provider"

class RedmineAiHelper::LlmClient::OpenAiProviderTest < ActiveSupport::TestCase
  context "OpenAiProvider" do
    setup do
      @provider = RedmineAiHelper::LlmClient::OpenAiProvider.new
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile
    end

    teardown do
      @setting.model_profile = @original_profile
      @setting.save!
    end

    should "configure RubyLLM with OpenAI API key" do
      @provider.configure_ruby_llm
      assert_equal @setting.model_profile.access_key, RubyLLM.config.openai_api_key
    end

    should "configure organization_id when present" do
      @provider.configure_ruby_llm
      assert_equal @setting.model_profile.organization_id, RubyLLM.config.openai_organization_id
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
      mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)
      RubyLLM.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)

      chat = @provider.create_chat(instructions: "Test prompt")
      assert_equal mock_chat, chat
    end
  end
end
