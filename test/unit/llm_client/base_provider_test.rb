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

    should "raise NotImplementedError when configure_ruby_llm is called" do
      assert_raises(NotImplementedError) do
        @provider.configure_ruby_llm
      end
    end

    should "return model name from model profile" do
      assert_equal @setting.model_profile.llm_model, @provider.model_name
    end

    should "return temperature from model profile" do
      assert_equal @setting.model_profile.temperature, @provider.temperature
    end

    should "return max_tokens from setting" do
      assert_equal @setting.max_tokens, @provider.max_tokens
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
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_instructions).with("Test instructions")
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        RubyLLM.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:configure_ruby_llm)

        chat = @provider.create_chat(instructions: "Test instructions")
        assert_equal mock_chat, chat
      end

      should "not call with_instructions when instructions is nil" do
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_instructions).never
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        RubyLLM.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:configure_ruby_llm)

        @provider.create_chat
      end

      should "call with_tools when tools are provided" do
        tool_class1 = mock("ToolClass1")
        tool_class2 = mock("ToolClass2")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_tools).with(tool_class1, tool_class2)
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        RubyLLM.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:configure_ruby_llm)

        @provider.create_chat(tools: [tool_class1, tool_class2])
      end

      should "not call with_tools when tools is empty" do
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_tools).never
        mock_chat.expects(:with_temperature).with(@setting.model_profile.temperature)

        RubyLLM.expects(:chat).with(model: @setting.model_profile.llm_model).returns(mock_chat)
        @provider.expects(:configure_ruby_llm)

        @provider.create_chat(tools: [])
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

      should "generate embedding using RubyLLM with default model" do
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([0.1, 0.2, 0.3])

        @provider.expects(:configure_ruby_llm)
        RubyLLM.expects(:embed).with("test text").returns(mock_response)

        @setting.embedding_model = nil
        @setting.save!

        result = @provider.embed("test text")
        assert_equal [0.1, 0.2, 0.3], result
      end

      should "use custom embedding model when configured" do
        mock_response = mock("EmbeddingResponse")
        mock_response.expects(:vectors).returns([0.4, 0.5, 0.6])

        @provider.expects(:configure_ruby_llm)
        RubyLLM.expects(:embed).with("test text", model: "text-embedding-ada-002").returns(mock_response)

        @setting.embedding_model = "text-embedding-ada-002"
        @setting.save!

        result = @provider.embed("test text")
        assert_equal [0.4, 0.5, 0.6], result
      end
    end
  end
end
