require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/leader_agent"

class LeaderAgentTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :enabled_modules
  setup do
    # Mock LLM provider
    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:model_name).returns("gpt-4")
    @mock_llm_provider.stubs(:temperature).returns(nil)
    @mock_llm_provider.stubs(:configure_ruby_llm)
    @mock_llm_provider.stubs(:create_chat).returns(mock("chat"))

    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)

    @params = {
      project: Project.find(1),
      langfuse: DummyLangfuse.new,
    }
    @agent = RedmineAiHelper::Agents::LeaderAgent.new(@params)
    @messages = [{ role: "user", content: "Hello" }]

    # Setup RubyLLM.chat mock for the chat method
    @mock_ruby_llm_chat = mock("RubyLLM::Chat")
    @mock_ruby_llm_chat.stubs(:with_instructions).returns(@mock_ruby_llm_chat)
    @mock_ruby_llm_chat.stubs(:with_temperature).returns(@mock_ruby_llm_chat)
    @mock_ruby_llm_chat.stubs(:add_message)
    RubyLLM.stubs(:chat).with(model: "gpt-4").returns(@mock_ruby_llm_chat)
  end

  context "LeaderAgent" do
    should "return correct role" do
      assert_equal "leader", @agent.role
    end

    should "return correct backstory" do
      backstory = @agent.backstory
      assert backstory.include?("You are the leader agent of the RedmineAIHelper plugin")
    end

    should "return correct system prompt" do
      system_prompt = @agent.system_prompt
      assert system_prompt.include?(@agent.backstory)
    end

    should "generate goal correctly" do
      goal_json = { "goal" => "test goal", "generate_steps_required" => true }.to_json
      mock_response = mock("Response")
      mock_response.stubs(:content).returns(goal_json)
      @mock_ruby_llm_chat.stubs(:ask).returns(mock_response)

      goal = @agent.generate_goal(@messages)
      assert goal.is_a?(Hash)
      assert_equal "test goal", goal["goal"]
    end

    should "generate steps correctly" do
      steps_json = {
        "steps" => [
          { "agent" => "project_agent", "step" => "my_projectのIDを教えてください", "description_for_human" => "Retrieving project information..." },
          { "agent" => "project_agent", "step" => "my_projectの情報を取得してください", "description_for_human" => "Getting project details..." },
        ],
      }.to_json
      mock_response = mock("Response")
      mock_response.stubs(:content).returns(steps_json)
      @mock_ruby_llm_chat.stubs(:ask).returns(mock_response)

      goal = "test goal"
      steps = @agent.generate_steps(goal, @messages)
      assert steps.is_a?(Hash)
      assert steps["steps"].is_a?(Array)
    end

    should "perform user request successfully" do
      # First call: generate_goal
      goal_json = { "goal" => "test goal", "generate_steps_required" => false }.to_json
      goal_response = mock("GoalResponse")
      goal_response.stubs(:content).returns(goal_json)

      # Second call: chat (when generate_steps_required is false, it falls through to chat)
      chat_response = mock("ChatResponse")
      chat_response.stubs(:content).returns("test answer")

      @mock_ruby_llm_chat.stubs(:ask).returns(goal_response).then.returns(chat_response)

      result = @agent.perform_user_request(@messages)
      assert result.is_a?(String)
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

