require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/leader_agent"

class LeaderAgentTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :enabled_modules
  setup do
    # Mock LLM provider
    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:model_name).returns("gpt-4")
    @mock_llm_provider.stubs(:temperature).returns(nil)

    # Mock chat instance returned by create_chat (used by both assistant and chat methods)
    @mock_ruby_llm_chat = mock("RubyLLM::Chat")
    @mock_ruby_llm_chat.stubs(:with_instructions).returns(@mock_ruby_llm_chat)
    @mock_ruby_llm_chat.stubs(:with_temperature).returns(@mock_ruby_llm_chat)
    @mock_ruby_llm_chat.stubs(:on_end_message).returns(@mock_ruby_llm_chat)
    @mock_ruby_llm_chat.stubs(:add_message)
    @mock_llm_provider.stubs(:create_chat).returns(@mock_ruby_llm_chat)

    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)

    @params = {
      project: Project.find(1),
      langfuse: DummyLangfuse.new
    }
    @agent = RedmineAiHelper::Agents::LeaderAgent.new(@params)
    @messages = [ { role: "user", content: "Hello" } ]
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
        ]
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

    should "include use_think_model boolean field in generate_steps JSON schema" do
      steps_json = {
        "steps" => [
          {
            "agent" => "wiki_agent",
            "step" => "Create a Wiki page.",
            "description_for_human" => "Creating Wiki page...",
            "use_think_model" => true
          },
        ]
      }.to_json
      mock_response = mock("Response")
      mock_response.stubs(:content).returns(steps_json)
      @mock_ruby_llm_chat.stubs(:ask).returns(mock_response)

      steps = @agent.generate_steps("test goal", @messages)
      assert steps["steps"].first.key?("use_think_model"), "Step should have use_think_model key"
      assert_equal true, steps["steps"].first["use_think_model"]
    end

    should "pass use_think_model: true for issue-answer step and false for retrieval step (US2 mixed)" do
      issue_answer_step = {
        "agent" => "issue_agent",
        "step" => "Write a detailed answer to Issue #42.",
        "description_for_human" => "Writing answer to Issue #42...",
        "use_think_model" => true
      }
      retrieval_step = {
        "agent" => "project_agent",
        "step" => "Get the project ID.",
        "description_for_human" => "Retrieving project ID...",
        "use_think_model" => false
      }
      steps_hash = { "steps" => [ issue_answer_step, retrieval_step ] }

      @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
      @agent.stubs(:generate_steps).returns(steps_hash)

      mock_issue_agent = mock("issue_agent")
      mock_issue_agent.stubs(:add_message)
      mock_project_agent = mock("project_agent")
      mock_project_agent.stubs(:add_message)

      agent_list = RedmineAiHelper::AgentList.instance
      agent_list.stubs(:get_agent_instance).with("issue_agent", anything).returns(mock_issue_agent)
      agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

      mock_chat_room = mock("chat_room")
      mock_chat_room.stubs(:add_agent)
      mock_chat_room.stubs(:share_goal)
      mock_chat_room.stubs(:messages).returns([])
      mock_chat_room.expects(:send_task).with("leader", "issue_agent", issue_answer_step["step"], { use_think_model: true })
      mock_chat_room.expects(:send_task).with("leader", "project_agent", retrieval_step["step"], { use_think_model: false })

      RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)
      @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

      @agent.perform_user_request(@messages)
    end

    should "pass use_think_model: true for code review step (US3)" do
      code_review_step = {
        "agent" => "repository_agent",
        "step" => "Review the code changes in the pull request.",
        "description_for_human" => "Performing code review...",
        "use_think_model" => true
      }
      steps_hash = { "steps" => [ code_review_step ] }

      @agent.stubs(:generate_goal).returns({ "goal" => "review code", "generate_steps_required" => true })
      @agent.stubs(:generate_steps).returns(steps_hash)

      mock_repo_agent = mock("repository_agent")
      mock_repo_agent.stubs(:add_message)

      agent_list = RedmineAiHelper::AgentList.instance
      agent_list.stubs(:get_agent_instance).with("repository_agent", anything).returns(mock_repo_agent)

      mock_chat_room = mock("chat_room")
      mock_chat_room.stubs(:add_agent)
      mock_chat_room.stubs(:share_goal)
      mock_chat_room.stubs(:messages).returns([])
      mock_chat_room.expects(:send_task).with("leader", "repository_agent", code_review_step["step"], { use_think_model: true })

      RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)
      @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

      @agent.perform_user_request(@messages)
    end

    should "pass use_think_model option to ChatRoom#send_task for each step" do
      wiki_step = {
        "agent" => "wiki_agent",
        "step" => "Create a Wiki page.",
        "description_for_human" => "Creating Wiki page...",
        "use_think_model" => true
      }
      retrieval_step = {
        "agent" => "project_agent",
        "step" => "Get project info.",
        "description_for_human" => "Retrieving project...",
        "use_think_model" => false
      }
      steps_hash = { "steps" => [ wiki_step, retrieval_step ] }

      @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
      @agent.stubs(:generate_steps).returns(steps_hash)

      mock_wiki_agent = mock("wiki_agent")
      mock_wiki_agent.stubs(:add_message)
      mock_project_agent = mock("project_agent")
      mock_project_agent.stubs(:add_message)

      agent_list = RedmineAiHelper::AgentList.instance
      agent_list.stubs(:get_agent_instance).with("wiki_agent", anything).returns(mock_wiki_agent)
      agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

      mock_chat_room = mock("chat_room")
      mock_chat_room.stubs(:add_agent)
      mock_chat_room.stubs(:share_goal)
      mock_chat_room.stubs(:messages).returns([])
      mock_chat_room.expects(:send_task).with("leader", "wiki_agent", wiki_step["step"], { use_think_model: true })
      mock_chat_room.expects(:send_task).with("leader", "project_agent", retrieval_step["step"], { use_think_model: false })

      RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)

      @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

      @agent.perform_user_request(@messages)
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

