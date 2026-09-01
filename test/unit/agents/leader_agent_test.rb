require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/leader_agent"

class LeaderAgentTest < ActiveSupport::TestCase
  # locale => [wording that must not appear, wording that must appear]
  # The forbidden entries are the "use only these results as the facts" phrasings: the
  # execution results carry step outcomes only, never the content of the answer, so an
  # instruction to treat them as the sole facts drops legitimate content from the reply
  # (FR-007a). The required entries point the model at the conversation for that content
  # (FR-006a).
  FINAL_RESPONSE_WORDING = {
    "en" => [ /Using only these results as the facts/i, /conversation above/i ],
    "ja" => [ /この結果のみを事実として/, /上記の会話/ ],
    "fr" => [ /uniquement sur ces résultats comme des faits/i, /conversation ci-dessus/i ],
    "it" => [ /Usando solo questi risultati come fatti/i, /conversazione precedente/i ],
    "tr" => [ /Yalnızca bu sonuçları gerçek olarak kullanarak/, /yukarıdaki konuşma/ ],
    "zh" => [ /仅将这些结果作为事实/, /上文对话/ ],
    "pt-BR" => [ /Usando apenas esses resultados como fatos/i, /conversa acima/i ],
    "fa" => [ /به‌عنوان تنها واقعیت‌ها/, /گفتگوی بالا/ ]
  }.freeze

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
    @mock_llm_provider.stubs(:supports_structured_output?).returns(false)

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

      assert_includes backstory, "You are the leader agent of the RedmineAIHelper plugin"
    end

    should "return correct system prompt" do
      system_prompt = @agent.system_prompt

      assert_includes system_prompt, @agent.backstory
    end

    should "generate goal correctly" do
      goal_json = { "goal" => "test goal", "generate_steps_required" => true }.to_json
      mock_response = mock("Response")
      mock_response.stubs(:content).returns(goal_json)
      @mock_ruby_llm_chat.stubs(:ask).returns(mock_response)

      goal = @agent.generate_goal(@messages)

      assert_kind_of Hash, goal
      assert_equal "test goal", goal["goal"]
    end

    context "structured_chat routing (US1)" do
      should "route generate_goal through structured_chat" do
        @agent.expects(:structured_chat).with(anything, json_schema: anything).returns(
          { "goal" => "routed goal", "generate_steps_required" => false }
        )

        goal = @agent.generate_goal(@messages)

        assert_equal "routed goal", goal["goal"]
      end

      should "route generate_steps through structured_chat" do
        @agent.expects(:structured_chat).with(anything, json_schema: anything).returns(
          { "steps" => [ { "agent" => "wiki_agent", "step" => "do x", "description_for_human" => "Doing x...", "use_think_model" => true, "requires_write" => true } ] }
        )

        steps = @agent.generate_steps("goal", @messages)

        assert_kind_of Array, steps["steps"]
      end
    end

    should "generate steps correctly" do
      steps_json = {
        "steps" => [
          { "agent" => "project_agent", "step" => "my_projectのIDを教えてください", "description_for_human" => "Retrieving project information...", "use_think_model" => false, "requires_write" => false },
          { "agent" => "project_agent", "step" => "my_projectの情報を取得してください", "description_for_human" => "Getting project details...", "use_think_model" => false, "requires_write" => false }
        ]
      }.to_json
      mock_response = mock("Response")
      mock_response.stubs(:content).returns(steps_json)
      @mock_ruby_llm_chat.stubs(:ask).returns(mock_response)

      goal = "test goal"
      steps = @agent.generate_steps(goal, @messages)

      assert_kind_of Hash, steps
      assert_kind_of Array, steps["steps"]
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

      assert_kind_of String, result
    end

    should "include use_think_model boolean field in generate_steps JSON schema" do
      steps_json = {
        "steps" => [
          {
            "agent" => "wiki_agent",
            "step" => "Create a Wiki page.",
            "description_for_human" => "Creating Wiki page...",
            "use_think_model" => true,
            "requires_write" => true
          }
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
        "agent" => "issue_read_agent",
        "step" => "Write a detailed answer to Issue #42.",
        "description_for_human" => "Writing answer to Issue #42...",
        "use_think_model" => true,
        "requires_write" => false
      }
      retrieval_step = {
        "agent" => "project_agent",
        "step" => "Get the project ID.",
        "description_for_human" => "Retrieving project ID...",
        "use_think_model" => false,
        "requires_write" => false
      }
      steps_hash = { "steps" => [ issue_answer_step, retrieval_step ] }

      @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
      @agent.stubs(:generate_steps).returns(steps_hash)

      mock_issue_read_agent = mock("issue_read_agent")
      mock_issue_read_agent.stubs(:add_message)
      mock_project_agent = mock("project_agent")
      mock_project_agent.stubs(:add_message)

      agent_list = RedmineAiHelper::AgentList.instance
      agent_list.stubs(:get_agent_instance).with("issue_read_agent", anything).returns(mock_issue_read_agent)
      agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

      mock_chat_room = mock("chat_room")
      mock_chat_room.stubs(:add_agent)
      mock_chat_room.stubs(:share_goal)
      mock_chat_room.stubs(:messages).returns([])
      mock_chat_room.stubs(:execution_results_json).returns("[]")
      mock_chat_room.expects(:send_task).with("leader", "issue_read_agent", issue_answer_step["step"], { use_think_model: true })
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
        "use_think_model" => true,
        "requires_write" => false
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
      mock_chat_room.stubs(:execution_results_json).returns("[]")
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
        "use_think_model" => true,
        "requires_write" => true
      }
      retrieval_step = {
        "agent" => "project_agent",
        "step" => "Get project info.",
        "description_for_human" => "Retrieving project...",
        "use_think_model" => false,
        "requires_write" => false
      }
      steps_hash = { "steps" => [ wiki_step, retrieval_step ] }

      @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
      @agent.stubs(:generate_steps).returns(steps_hash)

      mock_wiki_agent = mock("wiki_agent")
      mock_wiki_agent.stubs(:add_message)
      mock_wiki_agent.stubs(:can_write?).returns(true)
      mock_project_agent = mock("project_agent")
      mock_project_agent.stubs(:add_message)

      agent_list = RedmineAiHelper::AgentList.instance
      agent_list.stubs(:get_agent_instance).with("wiki_agent", anything).returns(mock_wiki_agent)
      agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

      mock_chat_room = mock("chat_room")
      mock_chat_room.stubs(:add_agent)
      mock_chat_room.stubs(:share_goal)
      mock_chat_room.stubs(:messages).returns([])
      mock_chat_room.stubs(:execution_results_json).returns("[]")
      mock_chat_room.expects(:send_task).with("leader", "wiki_agent", wiki_step["step"], { use_think_model: true })
      mock_chat_room.expects(:send_task).with("leader", "project_agent", retrieval_step["step"], { use_think_model: false })

      RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)

      @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

      @agent.perform_user_request(@messages)
    end

    context "generate_steps prompt content (FR-002a)" do
      should "not expose write capability to the LLM in the prompt (en)" do
        captured_content = nil
        @agent.expects(:structured_chat).with do |messages, _opts|
          captured_content = messages.last[:content]
          true
        end.returns({ "steps" => [] })

        @agent.generate_steps("test goal", @messages)

        assert_no_match(/can_write/, captured_content)
      end

      should "not expose write capability to the LLM in the prompt (ja)" do
        captured_content = nil
        @agent.expects(:structured_chat).with do |messages, _opts|
          captured_content = messages.last[:content]
          true
        end.returns({ "steps" => [] })

        I18n.with_locale(:ja) { @agent.generate_steps("test goal", @messages) }

        assert_no_match(/can_write/, captured_content)
      end
    end

    context "generate_steps requires_write schema" do
      should "include requires_write in the JSON schema without changing the list_agents call" do
        captured_schema = nil

        @agent.expects(:structured_chat).with do |_messages, opts|
          captured_schema = opts[:json_schema]
          true
        end.returns({ "steps" => [] })

        mock_agent_list = mock("agent_list")
        mock_agent_list.expects(:list_agents).with().at_least_once.returns([])
        RedmineAiHelper::AgentList.stubs(:instance).returns(mock_agent_list)

        @agent.generate_steps("test goal", @messages)

        items = captured_schema.dig(:properties, :steps, :items)
        assert_not_nil items, "steps.items must exist"
        assert items[:properties].key?(:requires_write), "items.properties must include requires_write"
        assert_equal "boolean", items[:properties][:requires_write][:type]
        assert_includes items[:required], "requires_write"
      end
    end

    context "runtime write-capability guard (US2)" do
      should "skip send_task and record a failure when a write step is assigned to a read-only agent, and continue with later steps" do
        write_step = {
          "agent" => "issue_read_agent",
          "step" => "Create an issue titled 'Clean the air conditioner'.",
          "description_for_human" => "Creating an issue...",
          "use_think_model" => true,
          "requires_write" => true
        }
        retrieval_step = {
          "agent" => "project_agent",
          "step" => "Get project info.",
          "description_for_human" => "Retrieving project...",
          "use_think_model" => false,
          "requires_write" => false
        }
        steps_hash = { "steps" => [ write_step, retrieval_step ] }

        @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
        @agent.stubs(:generate_steps).returns(steps_hash)

        mock_issue_read_agent = mock("issue_read_agent")
        mock_issue_read_agent.stubs(:add_message)
        mock_issue_read_agent.stubs(:can_write?).returns(false)
        mock_project_agent = mock("project_agent")
        mock_project_agent.stubs(:add_message)
        mock_project_agent.stubs(:can_write?).returns(false)

        agent_list = RedmineAiHelper::AgentList.instance
        agent_list.stubs(:get_agent_instance).with("issue_read_agent", anything).returns(mock_issue_read_agent)
        agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

        mock_chat_room = mock("chat_room")
        mock_chat_room.stubs(:add_agent)
        mock_chat_room.stubs(:share_goal)
        mock_chat_room.stubs(:messages).returns([])
        mock_chat_room.stubs(:execution_results_json).returns("[]")
        mock_chat_room.expects(:record_skipped_step).with(agent: "issue_read_agent", step: write_step["step"], error: anything)
        mock_chat_room.expects(:send_task).once.with("leader", "project_agent", retrieval_step["step"], { use_think_model: false })

        RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)
        @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

        @agent.perform_user_request(@messages)
      end

      should "still dispatch a read-only step assigned to a write-capable agent (FR-002a)" do
        # wiki_agent holds both read and write tools. A read-only step assigned to it must
        # not be blocked just because the agent happens to be write-capable.
        read_step = {
          "agent" => "wiki_agent",
          "step" => "Summarize the Wiki page 'ProjectOverview'.",
          "description_for_human" => "Reading the Wiki page...",
          "use_think_model" => false,
          "requires_write" => false
        }
        steps_hash = { "steps" => [ read_step ] }

        @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
        @agent.stubs(:generate_steps).returns(steps_hash)

        mock_wiki_agent = mock("wiki_agent")
        mock_wiki_agent.stubs(:add_message)
        mock_wiki_agent.stubs(:can_write?).returns(true)

        agent_list = RedmineAiHelper::AgentList.instance
        agent_list.stubs(:get_agent_instance).with("wiki_agent", anything).returns(mock_wiki_agent)

        mock_chat_room = mock("chat_room")
        mock_chat_room.stubs(:add_agent)
        mock_chat_room.stubs(:share_goal)
        mock_chat_room.stubs(:messages).returns([])
        mock_chat_room.stubs(:execution_results_json).returns("[]")
        mock_chat_room.expects(:record_skipped_step).never
        mock_chat_room.expects(:send_task).once.with("leader", "wiki_agent", read_step["step"], { use_think_model: false })

        RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)
        @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

        @agent.perform_user_request(@messages)
      end

      should "dispatch a write step assigned to a write-capable agent" do
        write_step = {
          "agent" => "wiki_agent",
          "step" => "Create a new Wiki page.",
          "description_for_human" => "Creating the Wiki page...",
          "use_think_model" => true,
          "requires_write" => true
        }
        steps_hash = { "steps" => [ write_step ] }

        @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
        @agent.stubs(:generate_steps).returns(steps_hash)

        mock_wiki_agent = mock("wiki_agent")
        mock_wiki_agent.stubs(:add_message)
        mock_wiki_agent.stubs(:can_write?).returns(true)

        agent_list = RedmineAiHelper::AgentList.instance
        agent_list.stubs(:get_agent_instance).with("wiki_agent", anything).returns(mock_wiki_agent)

        mock_chat_room = mock("chat_room")
        mock_chat_room.stubs(:add_agent)
        mock_chat_room.stubs(:share_goal)
        mock_chat_room.stubs(:messages).returns([])
        mock_chat_room.stubs(:execution_results_json).returns("[]")
        mock_chat_room.expects(:record_skipped_step).never
        mock_chat_room.expects(:send_task).once.with("leader", "wiki_agent", write_step["step"], { use_think_model: true })

        RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)
        @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

        @agent.perform_user_request(@messages)
      end
    end

    context "skipped steps are visible to later steps (FR-005c)" do
      should "add the unexecuted step to the shared history before the next step is dispatched" do
        write_step = {
          "agent" => "issue_read_agent",
          "step" => "Create an issue titled 'Clean the air conditioner'.",
          "description_for_human" => "Creating an issue...",
          "use_think_model" => true,
          "requires_write" => true
        }
        follow_up_step = {
          "agent" => "issue_write_agent",
          "step" => "Add a comment to the issue created in the previous step.",
          "description_for_human" => "Adding a comment...",
          "use_think_model" => false,
          "requires_write" => true
        }
        steps_hash = { "steps" => [ write_step, follow_up_step ] }

        @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
        @agent.stubs(:generate_steps).returns(steps_hash)

        mock_issue_read_agent = mock("issue_read_agent")
        mock_issue_read_agent.stubs(:role).returns("issue_read_agent")
        mock_issue_read_agent.stubs(:add_message)
        mock_issue_read_agent.stubs(:can_write?).returns(false)
        mock_issue_read_agent.expects(:perform_task).never

        mock_update_agent = mock("issue_write_agent")
        mock_update_agent.stubs(:role).returns("issue_write_agent")
        mock_update_agent.stubs(:add_message)
        mock_update_agent.stubs(:can_write?).returns(true)
        mock_update_agent.stubs(:perform_task).returns(
          RedmineAiHelper::BaseAgent::TaskResponse.create_success("comment added")
        )

        agent_list = RedmineAiHelper::AgentList.instance
        agent_list.stubs(:get_agent_instance).with("issue_read_agent", anything).returns(mock_issue_read_agent)
        agent_list.stubs(:get_agent_instance).with("issue_write_agent", anything).returns(mock_update_agent)

        # A real ChatRoom is used here: the point of this test is what actually lands in the
        # shared message history that later agents read.
        real_chat_room = RedmineAiHelper::ChatRoom.new("test goal")
        RedmineAiHelper::ChatRoom.stubs(:new).returns(real_chat_room)
        @mock_ruby_llm_chat.stubs(:ask).returns(stub(content: "final answer"))

        @agent.perform_user_request(@messages)

        skipped_index = real_chat_room.messages.index { |m| m[:content].match?(/not executed/i) }
        follow_up_index = real_chat_room.messages.index { |m| m[:content].include?(follow_up_step["step"]) }

        assert_not_nil skipped_index, "the guarded step must be added to the shared history"
        assert_not_nil follow_up_index
        assert skipped_index < follow_up_index,
               "the next agent must see the unexecuted step before receiving its own task"
      end
    end

    context "final answer reflects execution results (US2)" do
      should "pass chat_room's execution_results_json into the final response instruction" do
        step = {
          "agent" => "project_agent",
          "step" => "Get project info.",
          "description_for_human" => "Retrieving project...",
          "use_think_model" => false,
          "requires_write" => false
        }
        steps_hash = { "steps" => [ step ] }

        @agent.stubs(:generate_goal).returns({ "goal" => "test goal", "generate_steps_required" => true })
        @agent.stubs(:generate_steps).returns(steps_hash)

        mock_project_agent = mock("project_agent")
        mock_project_agent.stubs(:add_message)
        mock_project_agent.stubs(:can_write?).returns(false)

        agent_list = RedmineAiHelper::AgentList.instance
        agent_list.stubs(:get_agent_instance).with("project_agent", anything).returns(mock_project_agent)

        execution_json = '[{"agent":"issue_read_agent","step":"Create it.","status":"error","error":"no write capability"}]'
        mock_chat_room = mock("chat_room")
        mock_chat_room.stubs(:add_agent)
        mock_chat_room.stubs(:share_goal)
        mock_chat_room.stubs(:messages).returns([])
        mock_chat_room.stubs(:send_task)
        mock_chat_room.stubs(:execution_results_json).returns(execution_json)

        RedmineAiHelper::ChatRoom.stubs(:new).returns(mock_chat_room)

        captured_content = nil
        @mock_ruby_llm_chat.expects(:ask).with do |content, **_opts|
          captured_content = content
          true
        end.returns(stub(content: "final answer"))

        @agent.perform_user_request(@messages)

        assert_includes captured_content, "no write capability"
      end
    end

    context "system_prompt with read_only_mode (US3)" do
      should "include the read-only notice when read_only_mode is true" do
        AiHelperSetting.stubs(:read_only_mode?).returns(true)

        prompt = @agent.system_prompt

        assert_includes prompt, RedmineAiHelper::Util::PromptLoader.load_template("base_agent/read_only_notice").format
      end

      should "not include the read-only notice when read_only_mode is false" do
        AiHelperSetting.stubs(:read_only_mode?).returns(false)

        prompt = @agent.system_prompt

        assert_not_includes prompt, RedmineAiHelper::Util::PromptLoader.load_template("base_agent/read_only_notice").format
      end
    end

    context "generate_final_response locale content (US2)" do
      should "include %{execution_results} placeholder and drop success-presupposing wording in all locales" do
        old_wording = /All agents have completed their tasks|全てのエージェントがタスクを完了しました/

        FINAL_RESPONSE_WORDING.each_key do |locale|
          text = final_response_text(locale)

          assert_not_nil text, "#{locale}: generate_final_response key must exist"
          assert_includes text, "%{execution_results}", "#{locale}: must include the %{execution_results} placeholder"
          assert_no_match old_wording, text, "#{locale}: must not presuppose success"
        end
      end

      should "separate outcome judgement from answer content in all locales (FR-006a, FR-007a)" do
        FINAL_RESPONSE_WORDING.each do |locale, (forbidden, required)|
          text = final_response_text(locale)

          assert_no_match forbidden, text,
                          "#{locale}: must not ask the model to treat the execution results as the only facts"
          assert_match required, text,
                       "#{locale}: must point the model at the conversation for the content of the answer"
        end
      end
    end
  end

  # Reads the generate_final_response instruction straight from the locale YAML, so the
  # assertions cover the shipped file rather than whatever I18n has already loaded.
  def final_response_text(locale)
    yaml_path = File.expand_path("../../../../config/locales/#{locale}.yml", __FILE__)
    data = YAML.load_file(yaml_path)
    data.dig(locale, "ai_helper", "prompts", "leader_agent", "generate_final_response")
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
