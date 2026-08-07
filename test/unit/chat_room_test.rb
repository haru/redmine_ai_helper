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
