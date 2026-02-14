require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/base_agent"

class RedmineAiHelper::BaseAgentTest < ActiveSupport::TestCase
  def setup
    @project = Project.find(1)

    # Mock LLM provider
    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:model_name).returns("gpt-4")
    @mock_llm_provider.stubs(:temperature).returns(nil)
    @mock_llm_provider.stubs(:configure_ruby_llm)

    # Mock create_chat for assistant method
    @mock_chat = mock("RubyLLM::Chat")
    @mock_chat.stubs(:on_end_message).returns(@mock_chat)
    @mock_llm_provider.stubs(:create_chat).returns(@mock_chat)

    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)

    @params = {
      project: @project,
      langfuse: DummyLangfuse.new,
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
      assert providers.is_a?(Array)
      assert_equal [RedmineAiHelper::Tools::BoardTools], providers
    end

    should "return an empty array with agent2" do
      assert_equal [], @agent2.available_tool_providers
    end
  end

  context "available_tool_classes" do
    should "return an array of RubyLLM::Tool subclasses derived from available_tool_providers" do
      tool_classes = @agent.available_tool_classes
      assert tool_classes.is_a?(Array)
      assert tool_classes.length > 0
      tool_classes.each do |klass|
        assert klass < RubyLLM::Tool, "#{klass} should be a subclass of RubyLLM::Tool"
      end
      assert_equal RedmineAiHelper::Tools::BoardTools.tool_classes, tool_classes
    end

    should "return an empty array with agent2" do
      assert_equal [], @agent2.available_tool_classes
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
      assert tools.is_a?(Array)
      assert tools.length > 0
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
    should "use RubyLLM.chat to send messages and return answer" do
      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:with_instructions).returns(mock_chat_instance)
      mock_chat_instance.stubs(:with_temperature).returns(mock_chat_instance)
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("test answer")
      mock_chat_instance.stubs(:ask).returns(mock_response)

      RubyLLM.stubs(:chat).with(model: "gpt-4").returns(mock_chat_instance)

      messages = [
        { role: "user", content: "Hello" },
        { role: "assistant", content: "Hi there" },
        { role: "user", content: "What is Redmine?" },
      ]

      answer = @agent.chat(messages)
      assert_equal "test answer", answer
    end

    should "support streaming with callback" do
      # Use a real object to properly handle block arguments
      streaming_chat = StreamingMockChat.new(["chunk1", "chunk2"])
      RubyLLM.stubs(:chat).with(model: "gpt-4").returns(streaming_chat)

      messages = [{ role: "user", content: "Hello" }]
      chunks_received = []
      callback = ->(content) { chunks_received << content }

      answer = @agent.chat(messages, {}, callback)
      assert_equal ["chunk1", "chunk2"], chunks_received
      assert_equal "chunk1chunk2", answer
    end

    should "apply temperature when set" do
      @mock_llm_provider.stubs(:temperature).returns(0.7)

      mock_chat_instance = mock("RubyLLM::Chat")
      mock_chat_instance.stubs(:with_instructions).returns(mock_chat_instance)
      mock_chat_instance.expects(:with_temperature).with(0.7).returns(mock_chat_instance)
      mock_chat_instance.stubs(:on_end_message).returns(mock_chat_instance)
      mock_chat_instance.stubs(:add_message)

      mock_response = mock("Response")
      mock_response.stubs(:content).returns("answer")
      mock_chat_instance.stubs(:ask).returns(mock_response)

      RubyLLM.stubs(:chat).with(model: "gpt-4").returns(mock_chat_instance)

      messages = [{ role: "user", content: "Hello" }]
      @agent.chat(messages)
    end
  end

  context "perform_task" do
    should "perform the task and return a response" do
      mock_message = mock("message")
      mock_message.stubs(:role).returns(:user)
      mock_message.stubs(:content).returns("テストメッセージ")
      @mock_chat.stubs(:messages).returns([mock_message])

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
      [RedmineAiHelper::Tools::BoardTools]
    end

    def backstory
      "テストエージェントのバックストーリー"
    end

    def generate_response(prompt:, **options)
      "テストエージェントの応答"
    end
  end

  class TestAgent2 < RedmineAiHelper::BaseAgent
    def backstory
      "テストエージェント2のバックストーリー"
    end

    def generate_response(prompt:, **options)
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

    def generate_response(prompt:, **options)
      "無効化されたエージェントの応答"
    end
  end
end
