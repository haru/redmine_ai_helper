require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/azure_open_ai_provider"

class RedmineAiHelper::LlmClient::AzureOpenAiProviderTest < ActiveSupport::TestCase
  context "AzureOpenAiProvider" do
    setup do
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile

      @azure_profile = AiHelperModelProfile.create!(
        name: "Test Azure Profile",
        llm_type: "AzureOpenAi",
        llm_model: "gpt-4o",
        access_key: "test_azure_key",
        base_uri: "https://myresource.openai.azure.com/openai/deployments/gpt-4o",
      )
      @setting.model_profile = @azure_profile
      @setting.save!

      @provider = RedmineAiHelper::LlmClient::AzureOpenAiProvider.new
    end

    teardown do
      @setting.model_profile = @original_profile
      @setting.save!
      @azure_profile.destroy
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

    should "create chat with provider and assume_model_exists options" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).with("Test prompt")
      mock_chat.expects(:with_temperature).with(@azure_profile.temperature)
      mock_context.expects(:chat).with(
        model: @azure_profile.llm_model,
        provider: :openai,
        assume_model_exists: true,
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      chat = @provider.create_chat(instructions: "Test prompt")
      assert_equal mock_chat, chat
    end

    should "create chat without instructions when nil" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).never
      mock_chat.expects(:with_temperature).with(@azure_profile.temperature)
      mock_context.expects(:chat).with(
        model: @azure_profile.llm_model,
        provider: :openai,
        assume_model_exists: true,
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      @provider.create_chat
    end

    should "create chat with tools" do
      mock_context = mock("RubyLLM::Context")
      tool_class = mock("ToolClass")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_tools).with(tool_class)
      mock_chat.expects(:with_temperature).with(@azure_profile.temperature)
      mock_context.expects(:chat).with(
        model: @azure_profile.llm_model,
        provider: :openai,
        assume_model_exists: true,
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      @provider.create_chat(tools: [tool_class])
    end
  end
end
