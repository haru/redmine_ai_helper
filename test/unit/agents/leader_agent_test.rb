require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/leader_agent"

class LeaderAgentTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :enabled_modules
  setup do
    @openai_mock = MyOpenAI::DummyOpenAIClient.new
    Langchain::LLM::OpenAI.stubs(:new).returns(@openai_mock)
    @params = {
      access_token: "test_access_token",
      uri_base: "http://example.com",
      organization_id: "test_org_id",
      model: "test_model",
      project: Project.find(1),
      langfuse: DummyLangfuse.new,
    }
    @agent = RedmineAiHelper::Agents::LeaderAgent.new(@params)
    @messages = [{ role: "user", content: "Hello" }]
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
      goal = @agent.generate_goal(@messages)
      assert goal.is_a?(Hash)
      assert_equal "test goal", goal["goal"]
    end

    should "generate steps correctly" do
      goal = "test goal"
      steps = @agent.generate_steps(goal, @messages)
      assert steps.is_a?(Hash)
      assert steps["steps"].is_a?(Array)
    end

    should "perform user request successfully" do
      result = @agent.perform_user_request(@messages)
      assert result.is_a?(String)
    end
  end

  class DummyLangfuse
    def initialize(params = {})
      @params = params
    end

    def create_span(name:, input:)
      # Dummy implementation
    end

    def finish_current_span(output:)
      # Dummy implementation
    end

    def flush
      # Dummy implementation
    end
  end
end

module MyOpenAI
  class DummyOpenAIClient < Langchain::LLM::OpenAI
    attr_accessor :langfuse

    def initialize(params = {})
      super(api_key: "aaaa")
    end

    def chat(params = {})
      messages = params[:messages]
      message = messages.last[:content]

      answer = "test answer"

      if message.include?("clarify the user's request and set a clear goal")
        answer = {
          "goal" => "test goal",
          "generate_steps_required" => true
        }.to_json
      elsif message.include?("Please create instructions for other agents")
        answer = {
          "steps" => [
            { "agent" => "project_agent", "step" => "my_projectという名前のプロジェクトのIDを教えてください", "description_for_human" => "Retrieving project information..." },
            { "agent" => "project_agent", "step" => "my_projectの情報を取得してください", "description_for_human" => "Getting project details..." }
          ]
        }.to_json
      else
        answer = "test answer"
      end

      if block_given?
        { "index" => 0, "delta" => { "content" => "ら" }, "logprobs" => nil, "finish_reason" => nil }
        chunk = {
          "index": 0,
          "delta": { "content": answer },
          "finish_reason": nil,
        }.deep_stringify_keys
        yield(chunk)
      end

      response = { "choices": [{ "message": { "content": answer } }] }.deep_stringify_keys
      Langchain::LLM::OpenAIResponse.new(response)
    end
  end
end
