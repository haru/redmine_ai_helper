require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/base_provider"

class RedmineAiHelper::LlmClient::BaseProviderTest < ActiveSupport::TestCase
  # Test double with OpenAI provider metadata, used wherever a provider with a
  # non-nil ruby_llm_provider_class is needed (unlike the Compatible provider).
  class FakeOpenAiProvider < RedmineAiHelper::LlmClient::BaseProvider
    protected

    def ruby_llm_provider_class
      RubyLLM::Providers::OpenAI
    end

    def ruby_llm_provider_slug
      "openai"
    end

    def configure_provider_config(config)
      config.openai_api_key = resolved_model_profile.access_key
    end

    def build_context
      RubyLLM.context { |c| c.openai_api_key = "test_fetch_key" }
    end
  end

  context "BaseProvider" do
    setup do
      @provider = RedmineAiHelper::LlmClient::BaseProvider.new
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile
    end

    teardown do
      @setting.model_profile = @original_profile
      @setting.save!
    end

    should "raise NotImplementedError when build_context is called" do
      assert_raises(NotImplementedError) do
        @provider.context
      end
    end

    should "return model name from model profile" do
      assert_equal @setting.model_profile.llm_model, @provider.model_name
    end

    should "return temperature from model profile" do
      assert_equal @setting.model_profile.temperature, @provider.temperature
    end

    should "return max_tokens from model profile" do
      if @setting.model_profile.max_tokens.nil?
        assert_nil @provider.max_tokens
      else
        assert_equal @setting.model_profile.max_tokens, @provider.max_tokens
      end
    end

    should "raise error when model profile is missing for model_name" do
      @setting.model_profile = nil
      @setting.save!
      assert_raises(RuntimeError, "Model Profile not found") do
        @provider.model_name
      end
    end

    context "with explicit model_profile" do
      setup do
        @explicit_profile = AiHelperModelProfile.create!(
          name: "Explicit Think Profile",
          llm_model: "claude-3-7-sonnet-20250219",
          access_key: "think_key",
          temperature: 0.5,
          llm_type: "Anthropic",
          max_tokens: 4096
        )
        @provider_with_profile = RedmineAiHelper::LlmClient::BaseProvider.new(model_profile: @explicit_profile)
      end

      teardown do
        @explicit_profile.destroy
      end

      should "return model name from explicit profile, not from setting" do
        assert_equal "claude-3-7-sonnet-20250219", @provider_with_profile.model_name
        assert_not_equal @setting.model_profile.llm_model, @provider_with_profile.model_name
      end

      should "return temperature from explicit profile, not from setting" do
        assert_in_delta(0.5, @provider_with_profile.temperature)
      end

      should "return max_tokens from explicit profile, not from setting" do
        assert_equal @explicit_profile.max_tokens, @provider_with_profile.max_tokens
        if @setting.model_profile && @setting.model_profile.max_tokens
          assert_not_equal @setting.model_profile.max_tokens, @provider_with_profile.max_tokens
        end
      end
    end

    context "create_chat" do
      should "return a RubyLLM::Chat instance with instructions" do
        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_instructions).with("Test instructions")
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        chat = @provider.create_chat(instructions: "Test instructions")

        assert_equal mock_chat, chat
      end

      should "not call with_instructions when instructions is nil" do
        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_instructions).never
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat
      end

      should "call with_tools when tools are provided" do
        mock_context = mock("RubyLLM::Context")
        tool_class1 = mock("ToolClass1")
        tool_class2 = mock("ToolClass2")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_tools).with(tool_class1, tool_class2)
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat(tools: [ tool_class1, tool_class2 ])
      end

      should "not call with_tools when tools is empty" do
        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_tools).never
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat(tools: [])
      end

      should "reuse memoized context across multiple create_chat calls" do
        mock_context = mock("RubyLLM::Context")
        mock_chat1 = mock("RubyLLM::Chat1")
        mock_chat2 = mock("RubyLLM::Chat2")
        mock_chat1.stubs(:with_instructions)
        mock_chat1.stubs(:with_temperature)
        mock_chat2.stubs(:with_instructions)
        mock_chat2.stubs(:with_temperature)

        # build_context should be called only once
        @provider.expects(:build_context).once.returns(mock_context)
        mock_context.stubs(:chat).returns(mock_chat1, mock_chat2)

        @provider.create_chat
        @provider.create_chat
      end

      context "with apply_user_identifier" do
        setup do
          @original_send_user_id = @setting.send_user_id_enabled
        end

        teardown do
          @setting.send_user_id_enabled = @original_send_user_id
          @setting.save!
        end

        should "inject user id via create_chat when send_user_id_enabled is true" do
          @setting.send_user_id_enabled = true
          @setting.save!

          mock_context = mock("RubyLLM::Context")
          mock_chat = mock("RubyLLM::Chat")
          mock_chat.expects(:with_instructions).never
          mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)
          mock_chat.expects(:with_params).with(user: User.current.id.to_s).once

          mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
          @provider.expects(:build_context).returns(mock_context)

          @provider.create_chat
        end

        should "not inject user id via create_chat when send_user_id_enabled is false" do
          @setting.send_user_id_enabled = false
          @setting.save!

          mock_context = mock("RubyLLM::Context")
          mock_chat = mock("RubyLLM::Chat")
          mock_chat.expects(:with_instructions).never
          mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)
          mock_chat.expects(:with_params).never

          mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
          @provider.expects(:build_context).returns(mock_context)

          @provider.create_chat
        end
      end
    end

    context "embed" do
      setup do
        @original_embedding_model = @setting.embedding_model
      end

      teardown do
        @setting.embedding_model = @original_embedding_model
        @setting.save!
      end

      should "generate embedding using context with default model, forcing assume_model_exists when ruby_llm_provider_class is nil" do
        mock_context = mock("RubyLLM::Context")
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([ 0.1, 0.2, 0.3 ])

        @provider.expects(:build_context).returns(mock_context)
        mock_context.expects(:embed).with("test text", provider: :openai, assume_model_exists: true).returns(mock_response)

        @setting.embedding_model = nil
        @setting.save!

        result = @provider.embed("test text")

        assert_equal [ 0.1, 0.2, 0.3 ], result
      end

      should "use custom embedding model when configured, forcing assume_model_exists when ruby_llm_provider_class is nil" do
        mock_context = mock("RubyLLM::Context")
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([ 0.4, 0.5, 0.6 ])

        @provider.expects(:build_context).returns(mock_context)
        mock_context.expects(:embed).with("test text", model: "text-embedding-ada-002", provider: :openai, assume_model_exists: true).returns(mock_response)

        @setting.embedding_model = "text-embedding-ada-002"
        @setting.save!

        result = @provider.embed("test text")

        assert_equal [ 0.4, 0.5, 0.6 ], result
      end

      should "use a non-registry embedding model (e.g. Ollama via OpenAI Compatible) without raising" do
        mock_context = mock("RubyLLM::Context")
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([ 0.7, 0.8, 0.9 ])

        @provider.expects(:build_context).returns(mock_context)
        mock_context.expects(:embed).with("test text", model: "nomic-embed-text:latest", provider: :openai, assume_model_exists: true).returns(mock_response)

        @setting.embedding_model = "nomic-embed-text:latest"
        @setting.save!

        result = @provider.embed("test text")

        assert_equal [ 0.7, 0.8, 0.9 ], result
      end

      context "with a provider that has ruby_llm_provider_class present (e.g. OpenAI)" do
        setup do
          @concrete_provider = FakeOpenAiProvider.new
        end

        should "not force assume_model_exists or provider when ruby_llm_provider_class is present" do
          @concrete_provider.stubs(:ensure_model_registered!)
          mock_context = mock("RubyLLM::Context")
          mock_response = mock("EmbeddingResponse")
          mock_response.expects(:vectors).returns([ 0.1, 0.2, 0.3 ])

          @concrete_provider.expects(:build_context).returns(mock_context)
          mock_context.expects(:embed).with("test text", model: "text-embedding-ada-002").returns(mock_response)

          @setting.embedding_model = "text-embedding-ada-002"
          @setting.save!

          result = @concrete_provider.embed("test text")

          assert_equal [ 0.1, 0.2, 0.3 ], result
        end
      end
    end

    context "model registry integration" do
      setup do
        @test_model_id = "test-model-fetch-999"
        @test_profile = AiHelperModelProfile.create!(
          name: "Test Fetch Profile",
          llm_type: "OpenAI",
          llm_model: @test_model_id,
          access_key: "test_fetch_key"
        )
        @concrete_provider = FakeOpenAiProvider.new(model_profile: @test_profile)
        # Ensure test model not in registry at start
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @test_model_id }
      end

      teardown do
        @test_profile.destroy
        RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @test_model_id }
      end

      # T006
      should "model_in_registry? returns false when provider slug does not match" do
        # Register model with different provider
        other_model = RubyLLM::Model::Info.new(id: @test_model_id, provider: "anthropic", name: "Test Model")
        RubyLLM.models.instance_variable_get(:@models) << other_model

        assert_equal false, @concrete_provider.send(:model_in_registry?)
      end

      # T007
      should "model_in_registry? returns true when model ID and provider slug both match" do
        openai_model = RubyLLM::Model::Info.new(id: @test_model_id, provider: "openai", name: "Test Model")
        RubyLLM.models.instance_variable_get(:@models) << openai_model

        assert_equal true, @concrete_provider.send(:model_in_registry?)
      end

      # T008
      should "fetch_and_register_model! registers model when list_models contains the target" do
        fetched_model = RubyLLM::Model::Info.new(id: @test_model_id, provider: "openai", name: "New Model")
        mock_provider_instance = mock("RubyLLMProviderInstance")
        mock_provider_instance.expects(:list_models).returns([ fetched_model ])
        RubyLLM::Providers::OpenAI.expects(:new).returns(mock_provider_instance)

        @concrete_provider.send(:fetch_and_register_model!)

        assert @concrete_provider.send(:model_in_registry?), "Model should be registered after fetch"
      end

      # T009
      should "fetch_and_register_model! raises RuntimeError when model not in list_models" do
        mock_provider_instance = mock("RubyLLMProviderInstance")
        mock_provider_instance.expects(:list_models).returns([])
        RubyLLM::Providers::OpenAI.expects(:new).returns(mock_provider_instance)

        assert_raises(RuntimeError) do
          @concrete_provider.send(:fetch_and_register_model!)
        end
      end

      # T010
      should "ensure_model_registered! skips fetch when ruby_llm_provider_class is nil" do
        @provider.expects(:fetch_and_register_model!).never
        @provider.send(:ensure_model_registered!)
      end

      # T011
      should "ensure_model_registered! skips fetch when model already in registry" do
        openai_model = RubyLLM::Model::Info.new(id: @test_model_id, provider: "openai", name: "Existing Model")
        RubyLLM.models.instance_variable_get(:@models) << openai_model
        @concrete_provider.expects(:fetch_and_register_model!).never
        @concrete_provider.send(:ensure_model_registered!)
      end

      # T012
      should "ensure_model_registered! calls fetch_and_register_model! when model not in registry" do
        @concrete_provider.expects(:fetch_and_register_model!).once
        @concrete_provider.send(:ensure_model_registered!)
      end

      # T013
      should "context calls ensure_model_registered! only once (memoized)" do
        @concrete_provider.expects(:ensure_model_registered!).once
        @concrete_provider.stubs(:build_context).returns(mock("context"))
        @concrete_provider.context
        @concrete_provider.context
      end
    end

    context "abstract provider methods" do
      should "return nil for ruby_llm_provider_class" do
        assert_nil @provider.send(:ruby_llm_provider_class)
      end

      should "return nil for ruby_llm_provider_slug" do
        assert_nil @provider.send(:ruby_llm_provider_slug)
      end

      should "not raise for configure_provider_config (no-op)" do
        config = Object.new
        assert_nothing_raised do
          @provider.send(:configure_provider_config, config)
        end
      end
    end

    context "supports_user_identifier?" do
      should "return true by default" do
        assert_equal true, @provider.send(:supports_user_identifier?)
      end
    end

    context "supports_structured_output?" do
      should "return false when ruby_llm_provider_slug is nil" do
        assert_equal false, @provider.supports_structured_output?
      end

      should "return false for AzureOpenAiProvider (slug nil)" do
        azure_profile = AiHelperModelProfile.create!(
          name: "Azure SO", llm_type: "AzureOpenAi", llm_model: "gpt-4o",
          access_key: "k", base_uri: "https://x.azure.com"
        )
        provider = RedmineAiHelper::LlmClient::AzureOpenAiProvider.new(model_profile: azure_profile)

        assert_equal false, provider.supports_structured_output?
      ensure
        azure_profile&.destroy
      end

      should "return false for OpenAiCompatibleProvider (slug nil)" do
        compatible_profile = AiHelperModelProfile.create!(
          name: "Compat SO", llm_type: "OpenAICompatible", llm_model: "m",
          access_key: "k", base_uri: "https://x.com"
        )
        provider = RedmineAiHelper::LlmClient::OpenAiCompatibleProvider.new(model_profile: compatible_profile)

        assert_equal false, provider.supports_structured_output?
      ensure
        compatible_profile&.destroy
      end

      context "with a provider that has a ruby_llm_provider_slug" do
        setup do
          @so_model_id = "so-test-model-001"
          @so_profile = AiHelperModelProfile.create!(
            name: "SO Profile", llm_type: "OpenAI", llm_model: @so_model_id, access_key: "k"
          )
          @so_provider = FakeOpenAiProvider.new(model_profile: @so_profile)
        end

        teardown do
          @so_profile.destroy
          RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == @so_model_id }
        end

        should "return false when model is not in registry" do
          assert_equal false, @so_provider.supports_structured_output?
        end

        should "return the model structured_output? value when registered as capable" do
          capable = RubyLLM::Model::Info.new(
            id: @so_model_id, provider: "openai", name: "Capable", capabilities: %w[structured_output]
          )
          RubyLLM.models.instance_variable_get(:@models) << capable

          assert_equal true, @so_provider.supports_structured_output?
        end

        should "return false when registered model lacks structured_output capability" do
          incapable = RubyLLM::Model::Info.new(
            id: @so_model_id, provider: "openai", name: "Incapable", capabilities: %w[streaming]
          )
          RubyLLM.models.instance_variable_get(:@models) << incapable

          assert_equal false, @so_provider.supports_structured_output?
        end

        should "return false when the registry lookup raises an error" do
          RubyLLM.models.stubs(:by_provider).raises(StandardError.new("registry unavailable"))

          assert_equal false, @so_provider.supports_structured_output?
        end
      end
    end

    context "create_chat with schema" do
      should "apply with_schema when schema is provided" do
        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.stubs(:with_temperature)
        schema_payload = { name: "response", schema: { "type" => "object" }, strict: false }
        mock_chat.expects(:with_schema).with(schema_payload).returns(mock_chat)

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        chat = @provider.create_chat(schema: schema_payload)

        assert_equal mock_chat, chat
      end

      should "not call with_schema when schema is nil (existing behavior)" do
        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.stubs(:with_temperature)
        mock_chat.expects(:with_schema).never

        mock_context.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat
      end
    end

    context "apply_user_identifier" do
      setup do
        @original_send_user_id = @setting.send_user_id_enabled
        @original_current_user = User.current
      end

      teardown do
        @setting.send_user_id_enabled = @original_send_user_id
        @setting.save!
        User.current = @original_current_user
      end

      should "not call with_params when supports_user_identifier? is false" do
        @setting.send_user_id_enabled = true
        @setting.save!
        @provider.stubs(:supports_user_identifier?).returns(false)

        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_params).never

        @provider.send(:apply_user_identifier, mock_chat)
      end

      should "call chat.with_params with the current user's id when send_user_id_enabled is true" do
        @setting.send_user_id_enabled = true
        @setting.save!

        user = User.find(1)
        User.current = user

        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_params).with(user: user.id.to_s).once

        @provider.send(:apply_user_identifier, mock_chat)
      end

      should "not call chat.with_params when send_user_id_enabled is false" do
        @setting.send_user_id_enabled = false
        @setting.save!

        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_params).never

        @provider.send(:apply_user_identifier, mock_chat)
      end

      should "pass anonymous user id without special branching when enabled" do
        @setting.send_user_id_enabled = true
        @setting.save!

        User.current = User.anonymous

        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_params).with(user: User.anonymous.id.to_s).once

        @provider.send(:apply_user_identifier, mock_chat)
      end

      should "send different ids for different users" do
        @setting.send_user_id_enabled = true
        @setting.save!

        user_a = User.find(1)
        User.current = user_a
        mock_chat_a = mock("RubyLLM::Chat A")
        mock_chat_a.expects(:with_params).with(user: user_a.id.to_s).once
        @provider.send(:apply_user_identifier, mock_chat_a)

        user_b = User.anonymous
        User.current = user_b
        mock_chat_b = mock("RubyLLM::Chat B")
        mock_chat_b.expects(:with_params).with(user: user_b.id.to_s).once
        @provider.send(:apply_user_identifier, mock_chat_b)

        assert_not_equal user_a.id.to_s, user_b.id.to_s
      end
    end

    context "context isolation" do
      should "not pollute RubyLLM global configuration when using OpenAiCompatibleProvider" do
        original_api_base = RubyLLM.config.openai_api_base
        original_api_key = RubyLLM.config.openai_api_key

        compatible_profile = AiHelperModelProfile.create!(
          name: "Test Compatible Profile",
          llm_type: "OpenAICompatible",
          llm_model: "my-custom-model",
          access_key: "test_compatible_key",
          base_uri: "https://api.custom-llm.com/v1"
        )
        @setting.model_profile = compatible_profile
        @setting.save!

        provider = RedmineAiHelper::LlmClient::OpenAiCompatibleProvider.new
        provider.context

        if original_api_base.nil?
          assert_nil RubyLLM.config.openai_api_base
        else
          assert_equal original_api_base, RubyLLM.config.openai_api_base
        end
        if original_api_key.nil?
          assert_nil RubyLLM.config.openai_api_key
        else
          assert_equal original_api_key, RubyLLM.config.openai_api_key
        end

        compatible_profile.destroy
      end

      should "not pollute RubyLLM global configuration when using AzureOpenAiProvider" do
        original_api_base = RubyLLM.config.openai_api_base
        original_api_key = RubyLLM.config.openai_api_key

        azure_profile = AiHelperModelProfile.create!(
          name: "Test Azure Profile",
          llm_type: "AzureOpenAi",
          llm_model: "gpt-4o",
          access_key: "test_azure_key",
          base_uri: "https://myresource.openai.azure.com/openai/deployments/gpt-4o"
        )
        @setting.model_profile = azure_profile
        @setting.save!

        provider = RedmineAiHelper::LlmClient::AzureOpenAiProvider.new
        provider.context

        if original_api_base.nil?
          assert_nil RubyLLM.config.openai_api_base
        else
          assert_equal original_api_base, RubyLLM.config.openai_api_base
        end
        if original_api_key.nil?
          assert_nil RubyLLM.config.openai_api_key
        else
          assert_equal original_api_key, RubyLLM.config.openai_api_key
        end

        azure_profile.destroy
      end
    end
  end
end
