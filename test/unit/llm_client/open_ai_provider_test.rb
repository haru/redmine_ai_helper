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

    should "return a RubyLLM::Context" do
      assert_instance_of RubyLLM::Context, @provider.context
    end

    should "memoize the context" do
      context1 = @provider.context
      context2 = @provider.context
      assert_same context1, context2
    end

    should "raise error when model profile is missing" do
      @setting.model_profile = nil
      @setting.save!
      assert_raises(RuntimeError, "Model Profile not found") do
        @provider.context
      end
    end

    should "return RubyLLM::Providers::OpenAI for ruby_llm_provider_class" do
      assert_equal RubyLLM::Providers::OpenAI, @provider.send(:ruby_llm_provider_class)
    end

    should "return 'openai' for ruby_llm_provider_slug" do
      assert_equal "openai", @provider.send(:ruby_llm_provider_slug)
    end

    should "configure_provider_config sets openai_api_key" do
      config = RubyLLM::Configuration.new
      @provider.send(:configure_provider_config, config)
      assert_equal @setting.model_profile.access_key, config.openai_api_key
    end

    context "auto-fetch integration" do
      setup do
        @unregistered_model_id = "gpt-unregistered-test-999"
        @openai_profile = AiHelperModelProfile.create!(
          name: "Test Unregistered OpenAI Profile",
          llm_type: "OpenAI",
          llm_model: @unregistered_model_id,
          access_key: "test_openai_key",
        )
        @fetch_provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: @openai_profile)
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @unregistered_model_id }
      end

      teardown do
        @openai_profile.destroy
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @unregistered_model_id }
      end

      should "call list_models and register model when model is not in registry" do
        fetched_model = RubyLLM::Model::Info.new(
          id: @unregistered_model_id, provider: "openai", name: "GPT Unregistered Test",
        )
        mock_provider_instance = mock("RubyLLMProviderInstance")
        mock_provider_instance.expects(:list_models).returns([fetched_model])
        RubyLLM::Providers::OpenAI.expects(:new).returns(mock_provider_instance)

        @fetch_provider.context

        assert RubyLLM.models.by_provider("openai").any? { |m| m.id == @unregistered_model_id },
          "Unregistered model should be in registry after context call"
      end
    end

    should "create chat via base class" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).with("Test prompt")
      mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)
      mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      chat = @provider.create_chat(instructions: "Test prompt")
      assert_equal mock_chat, chat
    end
  end
end
