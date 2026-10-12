require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/anthropic_provider"
require "redmine_ai_helper/agents/leader_agent"
require "redmine_ai_helper/agents/project_agent"

class RedmineAiHelper::LlmClient::AnthropicProviderTest < ActiveSupport::TestCase
  fixtures :projects, :users

  # Renders the request payload the Anthropic protocol would send for the chat.
  # Calls RubyLLM internals (protocol_for / render_payload) on purpose, to check
  # the actual wire format; update this helper when upgrading RubyLLM.
  def payload_for_chat(chat)
    chat.provider.protocol_for(chat.model).new(chat.provider, chat.model).send(
      :render_payload,
      chat.messages,
      tools: chat.tools,
      temperature: chat.temperature,
      model: chat.model,
      caching: chat.caching,
      schema: chat.schema
    )
  end

  context "AnthropicProvider" do
    setup do
      @setting = AiHelperSetting.find_or_create
      @original_profile = @setting.model_profile

      @anthropic_profile = AiHelperModelProfile.create!(
        name: "Test Anthropic Profile",
        llm_type: "Anthropic",
        llm_model: "claude-sonnet-4-5-20250929",
        access_key: "test_anthropic_key",
        temperature: 0.5
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

    should "return a RubyLLM::Context" do
      assert_instance_of RubyLLM::Context, @provider.context
    end

    should "close every object in a native structured-output schema" do
      schema = {
        "type" => "object",
        "properties" => {
          "steps" => { "type" => "array", "items" => { "type" => "object", "properties" => { "a" => { "type" => "string" } } } },
          "open" => { "type" => "object", "additionalProperties" => true }
        }
      }
      prepared = @provider.send(:prepare_schema, name: "response", schema: schema, strict: false)

      assert_equal false, prepared[:schema]["additionalProperties"]
      assert_equal false, prepared[:schema]["properties"]["steps"]["items"]["additionalProperties"]
      assert_equal true, prepared[:schema]["properties"]["open"]["additionalProperties"]
      assert_nil schema["additionalProperties"]
    end

    should "send closed objects in the chat's output_config schema" do
      schema = { name: "response", strict: false, schema: { "type" => "object", "properties" => { "x" => { "type" => "string" } } } }
      chat = @provider.create_chat(instructions: "hi", schema: schema)
      payload = payload_for_chat(chat)

      assert_equal false, payload.dig(:output_config, :format, :schema, :additionalProperties)
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

    should "return RubyLLM::Providers::Anthropic for ruby_llm_provider_class" do
      assert_equal RubyLLM::Providers::Anthropic, @provider.send(:ruby_llm_provider_class)
    end

    should "return 'anthropic' for ruby_llm_provider_slug" do
      assert_equal "anthropic", @provider.send(:ruby_llm_provider_slug)
    end

    should "configure_provider_config sets anthropic_api_key" do
      config = RubyLLM::Configuration.new
      @provider.send(:configure_provider_config, config)

      assert_equal @anthropic_profile.access_key, config.anthropic_api_key
    end

    should "create chat via base class" do
      mock_context = mock("RubyLLM::Context")
      mock_chat = mock("RubyLLM::Chat")
      mock_chat.expects(:with_caching)
      mock_chat.expects(:with_instructions).with("Test prompt", cache_until_here: true)
      mock_chat.expects(:with_temperature).with(@anthropic_profile.temperature)
      mock_context.expects(:chat).with(model: @anthropic_profile.llm_model).returns(mock_chat)
      @provider.expects(:build_context).returns(mock_context)

      chat = @provider.create_chat(instructions: "Test prompt")

      assert_equal mock_chat, chat
    end

    context "supports_user_identifier?" do
      should "return false" do
        assert_equal false, @provider.send(:supports_user_identifier?)
      end
    end

    context "prompt caching" do
      setup do
        @instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "FIXED", variable: "VARIABLE")
      end

      should "add top-level cache_control and cache only the fixed system block" do
        payload = payload_for_chat(@provider.create_chat(instructions: @instructions))

        assert_equal({ type: "ephemeral" }, payload[:cache_control])
        assert_equal 2, payload[:system].size
        assert_equal "FIXED", payload[:system][0][:text]
        assert_equal({ type: "ephemeral" }, payload[:system][0][:cache_control])
        assert_equal "VARIABLE", payload[:system][1][:text]
        assert_nil payload[:system][1][:cache_control]
      end

      should "not specify a ttl" do
        payload = payload_for_chat(@provider.create_chat(instructions: @instructions))

        assert_nil payload[:cache_control][:ttl]
        assert_nil payload[:system][0][:cache_control][:ttl]
      end

      should "use a single system block when variable is empty" do
        instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "FIXED", variable: "")
        payload = payload_for_chat(@provider.create_chat(instructions: instructions))

        assert_equal 1, payload[:system].size
      end

      should "cache a String instruction as the first block" do
        payload = payload_for_chat(@provider.create_chat(instructions: "plain"))

        assert_equal({ type: "ephemeral" }, payload[:system][0][:cache_control])
      end

      should "only enable top-level caching when instructions are nil" do
        chat = @provider.create_chat
        payload = payload_for_chat(chat)

        assert_equal({ type: "ephemeral" }, payload[:cache_control])
        assert_empty(chat.messages.select { |m| m.role == :system })
      end

      should "send no cache_control and one system block when disabled" do
        @anthropic_profile.update!(prompt_caching_enabled: false)
        provider = RedmineAiHelper::LlmClient::AnthropicProvider.new
        payload = payload_for_chat(provider.create_chat(instructions: @instructions))

        assert_nil payload[:cache_control]
        assert_equal 1, payload[:system].size
        assert_equal "FIXED\n\nVARIABLE", payload[:system][0][:text]
        assert_nil payload[:system][0][:cache_control]
      end

      should "raise ArgumentError for an unsupported instructions type" do
        assert_raises(ArgumentError) { @provider.create_chat(instructions: { text: "prompt" }) }
      end

      context "with an explicit model profile" do
        setup do
          @other_profile = AiHelperModelProfile.create!(
            name: "Other Anthropic Profile",
            llm_type: "Anthropic",
            llm_model: "claude-sonnet-4-5-20250929",
            access_key: "other_anthropic_key"
          )
        end

        teardown do
          @other_profile.destroy
        end

        should "use the explicit profile's disabled setting over the global profile" do
          @other_profile.update!(prompt_caching_enabled: false)
          provider = RedmineAiHelper::LlmClient::AnthropicProvider.new(model_profile: @other_profile)
          payload = payload_for_chat(provider.create_chat(instructions: @instructions))

          assert_nil payload[:cache_control]
          assert_equal 1, payload[:system].size
        end

        should "use the explicit profile's enabled setting over the global profile" do
          @anthropic_profile.update!(prompt_caching_enabled: false)
          provider = RedmineAiHelper::LlmClient::AnthropicProvider.new(model_profile: @other_profile)
          payload = payload_for_chat(provider.create_chat(instructions: @instructions))

          assert_equal({ type: "ephemeral" }, payload[:cache_control])
          assert_equal 2, payload[:system].size
        end
      end

      context "with an agent's system prompt" do
        setup do
          User.current = users(:users_001)
          @agent_params = { project: projects(:projects_001) }
        end

        should "send the Leader Agent's prompt as a cached fixed block and an uncached context block" do
          agent = RedmineAiHelper::Agents::LeaderAgent.new(@agent_params)
          payload = payload_for_chat(agent.assistant.chat)

          assert_equal 2, payload[:system].size
          assert_includes payload[:system][0][:text], agent.backstory
          assert_equal({ type: "ephemeral" }, payload[:system][0][:cache_control])
          assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, payload[:system][1][:text])
          assert_nil payload[:system][1][:cache_control]
        end

        should "send a sub agent's prompt as a cached fixed block and an uncached time block" do
          agent = RedmineAiHelper::Agents::ProjectAgent.new(@agent_params)
          payload = payload_for_chat(agent.assistant.chat)

          assert_equal 2, payload[:system].size
          assert_includes payload[:system][0][:text], agent.backstory
          assert_equal({ type: "ephemeral" }, payload[:system][0][:cache_control])
          assert_match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, payload[:system][1][:text])
          assert_nil payload[:system][1][:cache_control]
        end
      end
    end
  end
end
