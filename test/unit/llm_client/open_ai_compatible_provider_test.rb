require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/open_ai_compatible_provider"

class RedmineAiHelper::LlmClient::OpenAiCompatibleProviderTest < ActiveSupport::TestCase
  context "OpenAiCompatibleProvider" do
    setup do
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile

      @compatible_profile = AiHelperModelProfile.create!(
        name: "Test Compatible Profile",
        llm_type: "OpenAICompatible",
        llm_model: "my-custom-model",
        access_key: "test_compatible_key",
        base_uri: "https://api.custom-llm.com/v1"
      )
      @setting.model_profile = @compatible_profile
      @setting.save!

      @provider = RedmineAiHelper::LlmClient::OpenAiCompatibleProvider.new
    end

    teardown do
      @setting.model_profile = @original_profile
      @setting.save!
      @compatible_profile.destroy
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

    should "raise error when base URI is missing" do
      # Clear the base_uri after creation to bypass model validation
      @compatible_profile.update_column(:base_uri, nil)
      assert_raises(RuntimeError, "Base URI not found") do
        @provider.context
      end
      # Restore for teardown
      @compatible_profile.update_column(:base_uri, "https://api.custom-llm.com/v1")
    end

    should "ensure_model_registered! is skipped because ruby_llm_provider_class is nil (FR-004)" do
      @provider.expects(:fetch_and_register_model!).never
      @provider.send(:ensure_model_registered!)
    end

    should "create chat with provider and assume_model_exists options" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).with("Test prompt")
      mock_chat.expects(:with_temperature).with(@compatible_profile.temperature)
      mock_context.expects(:chat).with(
        model: @compatible_profile.llm_model,
        provider: :openai,
        assume_model_exists: true
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      chat = @provider.create_chat(instructions: "Test prompt")

      assert_equal mock_chat, chat
    end

    should "create chat without instructions when nil" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_instructions).never
      mock_chat.expects(:with_temperature).with(@compatible_profile.temperature)
      mock_context.expects(:chat).with(
        model: @compatible_profile.llm_model,
        provider: :openai,
        assume_model_exists: true
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      @provider.create_chat
    end

    should "create chat with tools" do
      mock_context = mock("RubyLLM::Context")
      tool_class = mock("ToolClass")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_tools).with(tool_class)
      mock_chat.expects(:with_temperature).with(@compatible_profile.temperature)
      mock_context.expects(:chat).with(
        model: @compatible_profile.llm_model,
        provider: :openai,
        assume_model_exists: true
      ).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      @provider.create_chat(tools: [ tool_class ])
    end

    should "set openai_use_system_role to true in context config" do
      context = @provider.context

      assert_equal true, context.config.openai_use_system_role,
        "openai_use_system_role should be true for OpenAI-compatible providers to avoid sending 'developer' role"
    end

    context "apply_user_identifier" do
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
        mock_chat.expects(:with_temperature).with(@compatible_profile.temperature)
        mock_chat.expects(:with_params).with(user: User.current.id.to_s).once

        mock_context.expects(:chat).with(
          model: @compatible_profile.llm_model,
          provider: :openai,
          assume_model_exists: true
        ).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat
      end

      should "not inject user id when send_user_id_enabled is false" do
        @setting.send_user_id_enabled = false
        @setting.save!

        mock_context = mock("RubyLLM::Context")
        mock_chat = mock("RubyLLM::Chat")
        mock_chat.expects(:with_instructions).never
        mock_chat.expects(:with_temperature).with(@compatible_profile.temperature)
        mock_chat.expects(:with_params).never

        mock_context.expects(:chat).with(
          model: @compatible_profile.llm_model,
          provider: :openai,
          assume_model_exists: true
        ).returns(mock_chat)
        @provider.expects(:build_context).returns(mock_context)

        @provider.create_chat
      end
    end
  end
end
