require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/chat_room"

class RedmineAiHelper::ChatRoomTest < ActiveSupport::TestCase
  context "ChatRoom" do
    setup do
      @goal = "Complete the project successfully"
      @chat_room = RedmineAiHelper::ChatRoom.new(@goal)
      @mock_agent = mock("Agent")
      @mock_agent.stubs(:role).returns("mock_agent")
      @mock_agent.stubs(:perform_task).returns("Task completed")
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

      assert_equal "Task completed", response
      assert_equal 2, @chat_room.messages.size
      assert_match "Perform this task", @chat_room.messages[-2][:content]
      assert_match "Task completed", @chat_room.messages.last[:content]
    end

    should "raise error if agent not found" do
      error = assert_raises(RuntimeError) do
        @chat_room.send_task("leader", "non_existent_agent", "Perform this task")
      end
      assert_match "Agent not found: non_existent_agent", error.message
    end
  end
end
