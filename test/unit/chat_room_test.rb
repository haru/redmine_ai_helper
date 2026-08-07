require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/chat_room"

class RedmineAiHelper::ChatRoomTest < ActiveSupport::TestCase
  context "ChatRoom" do
    setup do
      @goal = "Complete the project successfully"
      @chat_room = RedmineAiHelper::ChatRoom.new(@goal)
      @mock_agent = mock("Agent")
      @mock_agent.stubs(:role).returns("mock_agent")
      @success_response = RedmineAiHelper::ToolResponse.create_success("Task completed")
      @mock_agent.stubs(:perform_task).returns(@success_response)
      @mock_agent.stubs(:add_message).returns(nil)
    end

    should "initialize with goal" do
      assert_equal @goal, @chat_room.goal
      assert_equal 0, @chat_room.messages.size
    end

    should "add agent" do
      @chat_room.add_agent(@mock_agent)

      assert_includes @chat_room.agents, @mock_agent
    end

    should "add message" do
      @chat_room.add_message("user", "leader", "Test message", "all")

      assert_equal 1, @chat_room.messages.size
      assert_match "Test message", @chat_room.messages.last[:content]
    end

    should "get agent by role" do
      @chat_room.add_agent(@mock_agent)
      agent = @chat_room.get_agent("mock_agent")

      assert_equal @mock_agent, agent
    end

    should "send task to agent and receive response" do
      @chat_room.add_agent(@mock_agent)
      response = @chat_room.send_task("leader", "mock_agent", "Perform this task")

      assert_equal @success_response, response
      assert_equal 2, @chat_room.messages.size
      assert_match "Perform this task", @chat_room.messages[-2][:content]
    end

    should "record the agent's reply text in the message history, not the raw response object" do
      @chat_room.add_agent(@mock_agent)
      @chat_room.send_task("leader", "mock_agent", "Perform this task")

      assert_match "Task completed", @chat_room.messages.last[:content]
      assert_no_match(/:status=>/, @chat_room.messages.last[:content])
    end

    should "record the error message in the message history when the task fails" do
      error_response = RedmineAiHelper::ToolResponse.create_error("boom")
      @mock_agent.stubs(:perform_task).returns(error_response)
      @chat_room.add_agent(@mock_agent)

      @chat_room.send_task("leader", "mock_agent", "Perform this task")

      assert_match "boom", @chat_room.messages.last[:content]
      assert_no_match(/:status=>/, @chat_room.messages.last[:content])
    end

    should "raise error if agent not found" do
      error = assert_raises(RuntimeError) do
        @chat_room.send_task("leader", "non_existent_agent", "Perform this task")
      end
      assert_match "Agent not found: non_existent_agent", error.message
    end

    context "step_results (US2)" do
      should "record a successful step result without an error key" do
        @chat_room.add_agent(@mock_agent)
        @chat_room.send_task("leader", "mock_agent", "Perform this task")

        result = @chat_room.step_results.last
        assert_equal "mock_agent", result[:agent]
        assert_equal "Perform this task", result[:step]
        assert_equal "success", result[:status]
        assert_not result.key?(:error)
      end

      should "record an error step result with the error message" do
        error_response = RedmineAiHelper::ToolResponse.create_error("boom")
        @mock_agent.stubs(:perform_task).returns(error_response)
        @chat_room.add_agent(@mock_agent)

        @chat_room.send_task("leader", "mock_agent", "Perform this task")

        result = @chat_room.step_results.last
        assert_equal "error", result[:status]
        assert_equal "boom", result[:error]
      end

      should "record a skipped step without calling perform_task" do
        @mock_agent.expects(:perform_task).never
        @chat_room.add_agent(@mock_agent)

        @chat_room.record_skipped_step(agent: "mock_agent", step: "Create an issue", error: "no write capability")

        result = @chat_room.step_results.last
        assert_equal "mock_agent", result[:agent]
        assert_equal "Create an issue", result[:step]
        assert_equal "error", result[:status]
        assert_equal "no write capability", result[:error]
      end

      should "share the skipped step with the other agents through the message history (FR-005c)" do
        @mock_agent.expects(:add_message).at_least_once
        @chat_room.add_agent(@mock_agent)

        @chat_room.record_skipped_step(agent: "mock_agent", step: "Create an issue", error: "no write capability")

        assert_equal 1, @chat_room.messages.size
        content = @chat_room.messages.last[:content]
        assert_match(/not executed/i, content)
        assert_includes content, "Create an issue"
        assert_includes content, "no write capability"
      end

      should "keep the skipped step visible to a step that runs after it (FR-005c)" do
        @chat_room.add_agent(@mock_agent)

        @chat_room.record_skipped_step(agent: "mock_agent", step: "Create an issue", error: "no write capability")
        @chat_room.send_task("leader", "mock_agent", "Add a comment to the created issue")

        skipped_index = @chat_room.messages.index { |m| m[:content].match?(/not executed/i) }
        follow_up_index = @chat_room.messages.index { |m| m[:content].include?("Add a comment to the created issue") }

        assert_not_nil skipped_index
        assert_not_nil follow_up_index
        assert skipped_index < follow_up_index,
               "the skipped step must be in the history before the following step is dispatched"
      end

      should "format step_results as a JSON array string in plan order" do
        @chat_room.add_agent(@mock_agent)
        @chat_room.send_task("leader", "mock_agent", "First task")
        @chat_room.record_skipped_step(agent: "mock_agent", step: "Second task", error: "no write capability")

        parsed = JSON.parse(@chat_room.execution_results_json)
        assert_equal 2, parsed.length
        assert_equal "success", parsed[0]["status"]
        assert_equal "error", parsed[1]["status"]
        assert_equal "Second task", parsed[1]["step"]
      end
    end
  end
end
