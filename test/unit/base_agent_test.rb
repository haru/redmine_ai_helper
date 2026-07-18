require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/base_agent"

class RedmineAiHelper::BaseAgentTest < ActiveSupport::TestCase
  def setup
    @project = Project.find(1)

    # Mock LLM provider
    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:model_name).returns("gpt-4")
    @mock_llm_provider.stubs(:temperature).returns(nil)

    # Mock create_chat for assistant method
    @mock_chat = mock("RubyLLM::Chat")
    @mock_chat.stubs(:on_end_message).returns(@mock_chat)
    @mock_llm_provider.stubs(:create_chat).returns(@mock_chat)

    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)

    @params = {
      project: @project,
      langfuse: DummyLangfuse.new
    }
    @agent = BaseAgentTestModele::TestAgent.new(@params)
    @agent2 = BaseAgentTestModele::TestAgent2.new(@params)
  end

  context "assistant" do
    should "return the instance of the agent" do
      assistant = @agent.assistant

      assert_instance_of RedmineAiHelper::Assistant, assistant
    end
  end

  context "available_tool_providers" do
    should "return an array of BaseTools subclasses with agent" do
      providers = @agent.available_tool_providers

      assert_kind_of Array, providers
      assert_equal [ RedmineAiHelper::Tools::BoardTools ], providers
    end

    should "return an empty array with agent2" do
      assert_equal [], @agent2.available_tool_providers
    end
  end

  context "available_tool_classes" do
    should "return an array of RubyLLM::Tool subclasses derived from available_tool_providers" do
      tool_classes = @agent.available_tool_classes

      assert_kind_of Array, tool_classes
      assert_operator tool_classes.length, :>, 0
      tool_classes.each do |klass|
        assert_operator klass, :<, RubyLLM::Tool, "#{klass} should be a subclass of RubyLLM::Tool"
      end
      assert_equal RedmineAiHelper::Tools::BoardTools.tool_classes, tool_classes
    end

    should "return an empty array with agent2" do
      assert_equal [], @agent2.available_tool_classes
    end
  end

  context "available_tool_classes with read_only_mode" do
    setup do
      @mixed_agent = BaseAgentTestModele::MixedToolsAgent.new(@params)
    end

    should "exclude write tool classes when read_only_mode is true" do
      AiHelperSetting.stubs(:read_only_mode?).returns(true)

      tool_classes = @mixed_agent.available_tool_classes

      assert tool_classes.none? { |klass| klass.write_tool? }, "write tools must be excluded"
      assert tool_classes.any? { |klass| !klass.write_tool? }, "read-only tools must remain"
    end

    should "include all tool classes when read_only_mode is false" do
      AiHelperSetting.stubs(:read_only_mode?).returns(false)

      tool_classes = @mixed_agent.available_tool_classes

      assert tool_classes.any? { |klass| klass.write_tool? }, "write tools must be included"
      assert tool_classes.any? { |klass| !klass.write_tool? }, "read-only tools must be included"
    end
  end

  context "system_prompt with read_only_mode" do
    should "include the read-only notice when read_only_mode is true" do
      AiHelperSetting.stubs(:read_only_mode?).returns(true)

      prompt = @agent.system_prompt

      assert_includes prompt, RedmineAiHelper::Util::PromptLoader.load_template("base_agent/read_only_notice").format
    end

    should "be identical to the default prompt when read_only_mode is false" do
      AiHelperSetting.stubs(:read_only_mode?).returns(false)

      prompt = @agent.system_prompt

      assert_not_includes prompt, RedmineAiHelper::Util::PromptLoader.load_template("base_agent/read_only_notice").format
    end
  end

  context "backstory" do
    should "return the backstory of the agent" do
      assert_equal "テストエージェントのバックストーリー", @agent.backstory
    end

    should "return the backstory of the agent2" do
      assert_equal "テストエージェント2のバックストーリー", @agent2.backstory
    end
  end

  context "available_tools" do
    should "return an array of tool info hashes with agent" do
      tools = @agent.available_tools

      assert_kind_of Array, tools
      assert_operator tools.length, :>, 0
      tools.each do |tool|
        assert tool.key?(:function), "Tool should have :function key"
        assert tool[:function].key?(:name), "Function should have :name"
        assert tool[:function].key?(:description), "Function should have :description"
      end
    end

    should "return an empty array with agent2" do
      assert_equal [], @agent2.available_tools
    end
  end

  context "enabled?" do
    should "return true by default for agents" do
      assert_equal true, @agent.enabled?
    end

    should "return true for agent2" do
      assert_equal true, @agent2.enabled?
    end
  end

  context "chat" do
    should "use create_chat to send messages and return answer" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("test answer")
      mock_chat_instance.stubs(:ask).returns(mock_response)

      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there" },
        { role: "user", content: "What is Redmine?" }
      ]

      answer = @agent.chat(messages)

      assert_equal "test answer", answer
    end

    should "support streaming with callback" do
      streaming_chat = StreamingMockChat.new([ "chunk1", "chunk2" ])
      @mock_llm_provider.stubs(:create_chat).returns(streaming_chat)

      messages = [ { role: "user", content: "Hello" } ]
      chunks_received = []
      callback = ->(content) { chunks_received << content }

      answer = @agent.chat(messages, {}, callback)

      assert_equal [ "chunk1", "chunk2" ], chunks_received
      assert_equal "chunk1chunk2", answer
    end

    should "propagate errors raised while reading streamed chunks" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      failing_chunk = mock("Chunk")
      failing_chunk.stubs(:content).raises(RuntimeError.new("stream read failed"))
      mock_chat_instance.expects(:ask).yields(failing_chunk)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      callback = ->(content) { }
      error = assert_raises(RuntimeError) do
        @agent.chat([ { role: "user", content: "Hello" } ], {}, callback)
      end
      assert_equal "stream read failed", error.message
    end

    should "pass system_prompt as instructions to create_chat" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("answer")
      mock_chat_instance.stubs(:ask).returns(mock_response)

      @mock_llm_provider.expects(:create_chat).with(instructions: @agent.system_prompt).returns(mock_chat_instance)

      messages = [ { role: "user", content: "Hello" } ]
      @agent.chat(messages)
    end

    should "pass with: parameter to ask when provided" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("image answer")
      image_paths = [ "/path/to/image.png" ]
      mock_chat_instance.expects(:ask).with("Describe this", with: image_paths).returns(mock_response)

      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      messages = [ { role: "user", content: "Describe this" } ]
      answer = @agent.chat(messages, {}, nil, with: image_paths)

      assert_equal "image answer", answer
    end

    should "not pass with: to ask when nil" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("text answer")
      mock_chat_instance.expects(:ask).with("Hello").returns(mock_response)

      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      messages = [ { role: "user", content: "Hello" } ]
      answer = @agent.chat(messages, {}, nil, with: nil)

      assert_equal "text answer", answer
    end
  end

  context "think_chat" do
    setup do
      @mock_think_provider = mock("think_llm_provider")
      @mock_think_provider.stubs(:model_name).returns("claude-3-7-sonnet")
      @mock_think_provider.stubs(:temperature).returns(nil)
      @mock_think_provider.stubs(:max_tokens).returns(4096)

      @mock_think_chat_instance = mock("RubyLLM::Chat think")
      @mock_think_chat_instance.stubs(:on_end_message).returns(@mock_think_chat_instance)
      @mock_think_chat_instance.stubs(:add_message)

      @mock_think_response = mock("Response think")
      @mock_think_response.stubs(:content).returns("think answer")
      @mock_think_chat_instance.stubs(:ask).returns(@mock_think_response)
      @mock_think_provider.stubs(:create_chat).returns(@mock_think_chat_instance)
    end

    should "delegate to @llm_provider when @think_llm_provider is nil" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(nil)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns("normal answer")
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      messages = [ { role: "user", content: "Hello" } ]
      answer = agent.think_chat(messages)

      assert_equal "normal answer", answer
    end

    should "use @think_llm_provider when set" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(@mock_think_provider)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      messages = [ { role: "user", content: "Complex question" } ]
      answer = agent.think_chat(messages)

      assert_equal "think answer", answer
    end

    should "lazily return think_llm_provider from LlmProvider.get_think_llm_provider" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(@mock_think_provider)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      assert_nil agent.instance_variable_get(:@think_llm_provider)
      assert_equal @mock_think_provider, agent.think_llm_provider
    end

    should "return nil from think_llm_provider when not configured" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(nil)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      assert_nil agent.think_llm_provider
    end
  end

  context "structured_chat" do
    setup do
      @json_schema = {
        "type" => "object",
        "properties" => { "goal" => { "type" => "string" } },
        "required" => [ "goal" ]
      }
      @mock_llm_provider.stubs(:supports_structured_output?).returns(false)
    end

    should "obtain a string response via chat and parse it with the schema" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns('{"goal": "structured"}')
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)

      assert_equal "structured", result["goal"]
    end

    should "propagate the with: parameter to chat" do
      image_paths = [ "/path/to/img.png" ]
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns('{"goal": "img"}')
      mock_chat_instance.expects(:ask).with("hi", with: image_paths).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema, with: image_paths)

      assert_equal "img", result["goal"]
    end

    should "retain the with: parameter when regenerating after a schema violation" do
      image_paths = [ "/path/to/img.png" ]
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      bad_response = mock("Response bad")
      bad_response.stubs(:content).returns('{"other": "no goal"}')
      good_response = mock("Response good")
      good_response.stubs(:content).returns('{"goal": "regenerated"}')
      mock_chat_instance.expects(:ask).with(anything, with: image_paths).twice.returns(bad_response, good_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema, with: image_paths)

      assert_equal "regenerated", result["goal"]
    end

    should "not rescue JSON::ParserError" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns("not parseable {{{")
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      assert_raises(JSON::ParserError) do
        @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)
      end
    end

    should "not rescue SchemaViolationError" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns('{"other": "no goal"}')
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      assert_raises(RedmineAiHelper::Util::StructuredOutputHelper::SchemaViolationError) do
        @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)
      end
    end
  end

  context "structured_chat native branch (US2)" do
    setup do
      @json_schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } }, "required" => [ "goal" ] }
    end

    should "call create_chat with a non-strict schema payload when supports_structured_output? is true" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns({ "goal" => "native" })
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.expects(:create_chat).with { |opts| opts.key?(:schema) && opts[:schema][:strict] == false && opts[:schema][:schema] == @json_schema }.returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)

      assert_equal "native", result["goal"]
    end

    should "skip JSON parsing when response.content is a Hash" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns({ "goal" => "hash-content" })
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)

      assert_equal "hash-content", result["goal"]
    end

    should "join the normal parse path when response.content is a String" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns('{"goal": "string-content"}')
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)

      assert_equal "string-content", result["goal"]
    end

    should "pass regeneration through the fallback chat method on schema violation (native)" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      # Native returns a non-conforming Hash first
      mock_response = mock("Response")
      mock_response.stubs(:content).returns({ "other" => "no goal" })
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)
      # Regeneration via fallback chat returns compliant JSON
      @agent.expects(:chat).with(anything, anything, anything, anything).returns('{"goal": "regenerated"}').at_least_once

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema)

      assert_equal "regenerated", result["goal"]
    end

    should "retain the with: parameter when regenerating via the fallback chat (native)" do
      image_paths = [ "/path/to/img.png" ]
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns({ "other" => "no goal" })
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)
      @agent.expects(:chat).with { |_msgs, _opt, _cb, **kw| kw[:with] == image_paths }.returns('{"goal": "regenerated"}')

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @json_schema, with: image_paths)

      assert_equal "regenerated", result["goal"]
    end
  end

  context "structured_chat native branch with an array-rooted schema" do
    setup do
      @array_schema = {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => { "corrected" => { "type" => "string" } },
          "required" => [ "corrected" ]
        }
      }
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)
    end

    should "wrap the array-rooted schema into an object payload for create_chat" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns({ "value" => [ { "corrected" => "the" } ] })
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.expects(:create_chat).with do |opts|
        opts[:schema][:schema]["type"] == "object" &&
          opts[:schema][:schema]["properties"].key?("value") &&
          opts[:schema][:schema]["properties"]["value"] == @array_schema
      end.returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @array_schema)

      assert_kind_of Array, result
      assert_equal "the", result.first["corrected"]
    end

    should "unwrap a String native response before validating against the array schema" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)
      mock_response = mock("Response")
      mock_response.stubs(:content).returns('{"value": [{"corrected": "the"}]}')
      mock_chat_instance.stubs(:ask).returns(mock_response)
      @mock_llm_provider.stubs(:create_chat).returns(mock_chat_instance)

      result = @agent.structured_chat([ { role: "user", content: "hi" } ], json_schema: @array_schema)

      assert_kind_of Array, result
      assert_equal "the", result.first["corrected"]
    end
  end

  context "format_instructions_for" do
    setup do
      @json_schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } } }
    end

    should "return an empty string when supports_structured_output? is true" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(true)

      assert_equal "", @agent.format_instructions_for(@json_schema)
    end

    should "return get_format_instructions result when supports_structured_output? is false" do
      @mock_llm_provider.stubs(:supports_structured_output?).returns(false)

      result = @agent.format_instructions_for(@json_schema)

      assert_includes result, "JSON Schema"
    end
  end

  context "extract_text_content" do
    should "return text as-is for plain string content" do
      result = @agent.send(:extract_text_content, "Hello world")

      assert_equal "Hello world", result
    end

    should "return nil for nil content" do
      result = @agent.send(:extract_text_content, nil)

      assert_nil result
    end

    should "return text from RubyLLM::Content object" do
      content = RubyLLM::Content.new("Image description text", [])
      result = @agent.send(:extract_text_content, content)

      assert_equal "Image description text", result
    end

    should "return text from RubyLLM::Content with attachments, stripping binary data" do
      # Create a temporary image file
      tmpfile = Tempfile.new([ "test_image", ".png" ])
      tmpfile.binmode
      # PNG header bytes
      tmpfile.write("\x89PNG\r\n\x1a\n")
      tmpfile.flush

      content = RubyLLM::Content.new("Describe this image", [ tmpfile.path ])
      result = @agent.send(:extract_text_content, content)

      assert_equal "Describe this image", result
    ensure
      tmpfile&.close
      tmpfile&.unlink
    end
  end

  context "@shared_messages tracking" do
    should "initialize @shared_messages as empty array" do
      assert_equal [], @agent.instance_variable_get(:@shared_messages)
    end

    should "append to @shared_messages when add_message is called" do
      @mock_chat.stubs(:add_message)
      @agent.add_message(role: "user", content: "hello")
      shared = @agent.instance_variable_get(:@shared_messages)

      assert_equal 1, shared.length
      assert_equal({ role: "user", content: "hello" }, shared.first)
    end

    should "also forward add_message to assistant" do
      @mock_chat.expects(:add_message).with(role: :user, content: "hello")
      @agent.add_message(role: "user", content: "hello")
    end
  end

  context "build_think_assistant" do
    setup do
      @mock_think_provider = mock("think_llm_provider")
      @mock_think_provider.stubs(:model_name).returns("claude-3-7-sonnet")
      @mock_think_provider.stubs(:temperature).returns(nil)
      @mock_think_provider.stubs(:max_tokens).returns(4096)

      @mock_think_chat = mock("think_chat")
      @mock_think_chat.stubs(:on_end_message).returns(@mock_think_chat)
      @mock_think_chat.stubs(:add_message)
      @mock_think_chat.stubs(:messages).returns([])
      @mock_think_provider.stubs(:create_chat).returns(@mock_think_chat)
    end

    should "use think_llm_provider when available" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(@mock_think_provider)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      mock_think_response = mock("response")
      mock_think_response.stubs(:content).returns("think result")
      @mock_think_chat.stubs(:run).returns([ mock_think_response ])

      @mock_think_provider.expects(:create_chat).at_least_once.returns(@mock_think_chat)

      result = agent.send(:build_think_assistant)

      assert_not_nil result
    end

    should "fall back to @llm_provider when think_llm_provider is nil" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(nil)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      mock_response = mock("response")
      mock_response.stubs(:content).returns("regular result")
      @mock_chat.stubs(:run).returns([ mock_response ])

      @mock_llm_provider.expects(:create_chat).at_least_once.returns(@mock_chat)

      result = agent.send(:build_think_assistant)

      assert_not_nil result
    end

    should "replay @shared_messages to the new think assistant" do
      RedmineAiHelper::LlmProvider.stubs(:get_think_llm_provider).returns(@mock_think_provider)
      agent = BaseAgentTestModele::TestAgent.new(@params)

      @mock_chat.stubs(:add_message)
      agent.add_message(role: "user", content: "first message")
      agent.add_message(role: "assistant", content: "first reply")

      @mock_think_chat.expects(:add_message).with(role: :user, content: "first message")
      @mock_think_chat.expects(:add_message).with(role: :assistant, content: "first reply")

      agent.send(:build_think_assistant)
    end
  end

  context "perform_task with use_think_model option" do
    setup do
      @mock_think_assistant = mock("think_assistant")
      mock_msg = mock("think_msg")
      mock_msg.stubs(:content).returns("think task")
      @mock_think_assistant.stubs(:messages).returns([ mock_msg ])
      @mock_task_response = RedmineAiHelper::BaseAgent::TaskResponse.create_success("ok")
    end

    should "call build_think_assistant when use_think_model is true" do
      agent = BaseAgentTestModele::TestAgent.new(@params)
      agent.stubs(:dispatch).returns(@mock_task_response)
      agent.expects(:build_think_assistant).returns(@mock_think_assistant)

      response = agent.perform_task({ use_think_model: true })

      assert response
    end

    should "not call build_think_assistant when use_think_model is false" do
      agent = BaseAgentTestModele::TestAgent.new(@params)
      mock_msg = mock("reg_msg")
      mock_msg.stubs(:content).returns("task")
      @mock_chat.stubs(:messages).returns([ mock_msg ])
      agent.stubs(:dispatch).returns(@mock_task_response)
      agent.expects(:build_think_assistant).never

      response = agent.perform_task({ use_think_model: false })

      assert response
    end

    should "not call build_think_assistant when use_think_model is absent" do
      agent = BaseAgentTestModele::TestAgent.new(@params)
      mock_msg = mock("reg_msg")
      mock_msg.stubs(:content).returns("task")
      @mock_chat.stubs(:messages).returns([ mock_msg ])
      agent.stubs(:dispatch).returns(@mock_task_response)
      agent.expects(:build_think_assistant).never

      response = agent.perform_task({})

      assert response
    end
  end

  context "perform_task" do
    should "perform the task and return a response" do
      mock_message = mock("message")
      mock_message.stubs(:role).returns(:user)
      mock_message.stubs(:content).returns("テストメッセージ")
      @mock_chat.stubs(:messages).returns([ mock_message ])

      mock_response = mock("response")
      mock_response.stubs(:content).returns("test response")
      @mock_chat.stubs(:ask).with("テストメッセージ").returns(mock_response)
      @mock_chat.stubs(:add_message)

      response = @agent.perform_task({})

      assert response
    end
  end

  context "AgentList" do
    setup do
      @agent_list = RedmineAiHelper::AgentList.instance
      @original_agents = @agent_list.instance_variable_get(:@agents).dup
      @agent_list.instance_variable_set(:@agents, [])
      @agent_list.add_agent("test_agent", "BaseAgentTestModele::TestAgent")
      @agent_list.add_agent("test_agent2", "BaseAgentTestModele::TestAgent2")
      @agent_list.add_agent("disabled_agent", "BaseAgentTestModele::DisabledAgent")
    end

    teardown do
      @agent_list.instance_variable_set(:@agents, @original_agents)
    end

    should "return only enabled agents in list_agents" do
      agents = @agent_list.list_agents
      agent_names = agents.map { |a| a[:agent_name] }

      assert_includes agent_names, "test_agent"
      assert_includes agent_names, "test_agent2"
      assert_not_includes agent_names, "disabled_agent"
    end
  end

  class DummyLangfuse
    def initialize(params = {})
      @params = params
    end

    def create_span(name:, input:)
    end

    def finish_current_span(output:)
    end

    def flush
    end
  end
end

# Helper class to simulate RubyLLM::Chat with streaming support
class StreamingMockChat
  def initialize(chunks)
    @chunks = chunks
  end

  def with_instructions(_text)
    self
  end

  def with_temperature(_temp)
    self
  end

  def on_end_message(&_block)
    self
  end

  def add_message(**_kwargs)
  end

  def ask(_content)
    @chunks.each do |chunk_text|
      yield OpenStruct.new(content: chunk_text)
    end
  end
end

module BaseAgentTestModele
  class TestAgent < RedmineAiHelper::BaseAgent
    def available_tool_providers
      [ RedmineAiHelper::Tools::BoardTools ]
    end

    def backstory
      "テストエージェントのバックストーリー"
    end

    def generate_response(_prompt:, **_options)
      "テストエージェントの応答"
    end
  end

  class TestAgent2 < RedmineAiHelper::BaseAgent
    def backstory
      "テストエージェント2のバックストーリー"
    end

    def generate_response(_prompt:, **_options)
      "テストエージェントの応答"
    end
  end

  class DisabledAgent < RedmineAiHelper::BaseAgent
    def backstory
      "無効化されたテストエージェント"
    end

    def enabled?
      false
    end

    def generate_response(_prompt:, **_options)
      "無効化されたエージェントの応答"
    end
  end

  class MixedTools < RedmineAiHelper::BaseTools
    define_function :read_something, description: "Reads something" do
      property :id, type: "integer", description: "The ID", required: true
    end

    define_function :write_something, description: "Writes something", write: true do
      property :id, type: "integer", description: "The ID", required: true
    end

    def read_something(id:)
      id
    end

    def write_something(id:)
      id
    end
  end

  class MixedToolsAgent < RedmineAiHelper::BaseAgent
    def available_tool_providers
      [ BaseAgentTestModele::MixedTools ]
    end

    def backstory
      "書き込みツールテスト用エージェントのバックストーリー"
    end

    def generate_response(_prompt:, **_options)
      "書き込みツールテスト用エージェントの応答"
    end
  end
end
