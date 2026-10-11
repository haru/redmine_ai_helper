require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/open_ai_provider"

class RedmineAiHelper::LlmClient::OpenAiProviderTest < ActiveSupport::TestCase
  context "OpenAiProvider" do
    setup do
      @provider = RedmineAiHelper::LlmClient::OpenAiProvider.new
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile
      # FR-005: the "create chat via base class" test covers the
      # explicit-temperature path. A recreated setting profile now starts
      # with a nil temperature (the column default was removed), so pin a
      # value when needed. The test transaction rollback restores the
      # original value.
      @original_profile.update_columns(temperature: 0.5) if @original_profile.temperature.nil?
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

    should "configure_provider_config sets openai_organization_id when present" do
      profile = AiHelperModelProfile.create!(
        name: "OpenAI Org Profile",
        llm_type: "OpenAI",
        llm_model: "gpt-4o",
        access_key: "test_key",
        organization_id: "org-test123"
      )
      provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: profile)
      config = RubyLLM::Configuration.new
      provider.send(:configure_provider_config, config)

      assert_equal "org-test123", config.openai_organization_id
      profile.destroy
    end

    should "configure_provider_config sets http_proxy when present" do
      profile = AiHelperModelProfile.create!(
        name: "OpenAI Proxy Profile",
        llm_type: "OpenAI",
        llm_model: "gpt-4o",
        access_key: "test_key",
        http_proxy: "http://localhost:3128"
      )
      provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: profile)
      config = RubyLLM::Configuration.new
      provider.send(:configure_provider_config, config)

      assert_equal "http://localhost:3128", config.http_proxy
      profile.destroy
    end

    should "configure_provider_config does not set openai_organization_id when absent" do
      profile = AiHelperModelProfile.create!(
        name: "OpenAI No Org Profile",
        llm_type: "OpenAI",
        llm_model: "gpt-4o",
        access_key: "test_key"
      )
      provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: profile)
      config = RubyLLM::Configuration.new
      provider.send(:configure_provider_config, config)

      assert_nil config.openai_organization_id
      profile.destroy
    end

    context "auto-fetch integration" do
      setup do
        @unregistered_model_id = "gpt-unregistered-test-999"
        @openai_profile = AiHelperModelProfile.create!(
          name: "Test Unregistered OpenAI Profile",
          llm_type: "OpenAI",
          llm_model: @unregistered_model_id,
          access_key: "test_openai_key"
        )
        @fetch_provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: @openai_profile)
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @unregistered_model_id }
      end

      teardown do
        @openai_profile.destroy
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @unregistered_model_id }
      end

      should "call list_models and register model when model is not in registry" do
        fetched_model = RubyLLM::Model.new(
          id: @unregistered_model_id, provider: "openai", name: "GPT Unregistered Test"
        )
        mock_provider_instance = mock("RubyLLMProviderInstance")
        mock_provider_instance.expects(:list_models).returns([ fetched_model ])
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

    should "not pass protocol or reasoning options to context.chat so RubyLLM decides the API (FR-013)" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.stubs(:with_temperature)
      mock_chat.expects(:with_provider_options).never
      mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      @provider.create_chat
    end

    %w[gpt-6-luna gpt-6-sol gpt-5].each do |model_id|
      should "let RubyLLM use the Responses API for #{model_id}" do
        config = RubyLLM::Configuration.new
        config.openai_api_key = "test_key"
        openai = RubyLLM::Providers::OpenAI.new(config)
        model = RubyLLM::Model.default(model_id, "openai")

        assert_equal openai.protocols[:responses], openai.protocol_for(model)
        assert_not_equal openai.protocols[:chat_completions], openai.protocol_for(model)
      end
    end

    context "create_chat with Instructions" do
      should "send one system message without cache markers" do
        instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "FIXED", variable: "VARIABLE")
        chat = @provider.create_chat(instructions: instructions)
        system_messages = chat.messages.select { |m| m.role == :system }

        assert_equal 1, system_messages.size
        assert_equal "FIXED\n\nVARIABLE", system_messages.first.content
        assert_equal false, system_messages.first.cache_until_here?
      end
    end
  end
end
