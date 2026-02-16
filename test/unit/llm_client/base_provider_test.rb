require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/base_provider"

class RedmineAiHelper::LlmClient::BaseProviderTest < ActiveSupport::TestCase
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

    should "return max_tokens from setting" do
      if @setting.max_tokens.nil?
        assert_nil @provider.max_tokens
      else
        assert_equal @setting.max_tokens, @provider.max_tokens
      end
    end

    should "raise error when model profile is missing for model_name" do
      @setting.model_profile = nil
      @setting.save!
      assert_raises(RuntimeError, "Model Profile not found") do
        @provider.model_name
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

        @provider.create_chat(tools: [tool_class1, tool_class2])
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
    end

    context "embed" do
      setup do
        @original_embedding_model = @setting.embedding_model
      end

      teardown do
        @setting.embedding_model = @original_embedding_model
        @setting.save!
      end

      should "generate embedding using context with default model" do
        mock_context = mock("RubyLLM::Context")
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([0.1, 0.2, 0.3])

        @provider.expects(:build_context).returns(mock_context)
        mock_context.expects(:embed).with("test text").returns(mock_response)

        @setting.embedding_model = nil
        @setting.save!

        result = @provider.embed("test text")
        assert_equal [0.1, 0.2, 0.3], result
      end

      should "use custom embedding model when configured" do
        mock_context = mock("RubyLLM::Context")
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([0.4, 0.5, 0.6])

        @provider.expects(:build_context).returns(mock_context)
        mock_context.expects(:embed).with("test text", model: "text-embedding-ada-002").returns(mock_response)

        @setting.embedding_model = "text-embedding-ada-002"
        @setting.save!

        result = @provider.embed("test text")
        assert_equal [0.4, 0.5, 0.6], result
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
          base_uri: "https://api.custom-llm.com/v1",
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
          base_uri: "https://myresource.openai.azure.com/openai/deployments/gpt-4o",
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
