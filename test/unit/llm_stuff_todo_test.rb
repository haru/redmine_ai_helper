require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/llm"

class RedmineAiHelper::LlmStuffTodoTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations

  context "stuff_todo" do
    setup do
      @project = Project.find(1)
      @user = User.find(2)
      User.current = @user

      @params = {
        access_token: "test_access_token",
        uri_base: "http://example.com",
        organization_id: "test_org_id",
      }
      @llm = RedmineAiHelper::Llm.new(@params)
    end

    should "call IssueAgent#suggest_stuff_todo" do
      # Mock IssueAgent
      mock_agent = mock("IssueAgent")
      mock_agent.expects(:suggest_stuff_todo).with(stream_proc: nil).returns("Suggested tasks")

      RedmineAiHelper::Agents::IssueAgent.expects(:new).with(
        project: @project,
        langfuse: instance_of(RedmineAiHelper::LangfuseUtil::LangfuseWrapper)
      ).returns(mock_agent)

      result = @llm.stuff_todo(project: @project)

      assert_equal "Suggested tasks", result
    end

    should "support streaming response" do
      # Mock IssueAgent
      mock_agent = mock("IssueAgent")

      streamed_content = []
      stream_proc = Proc.new { |content| streamed_content << content }

      mock_agent.expects(:suggest_stuff_todo).with(stream_proc: stream_proc).returns("Final result")

      RedmineAiHelper::Agents::IssueAgent.expects(:new).returns(mock_agent)

      result = @llm.stuff_todo(project: @project, stream_proc: stream_proc)

      assert_equal "Final result", result
    end

    should "handle errors gracefully" do
      # Mock IssueAgent to raise error
      mock_agent = mock("IssueAgent")
      mock_agent.expects(:suggest_stuff_todo).raises(StandardError.new("Test error"))

      RedmineAiHelper::Agents::IssueAgent.expects(:new).returns(mock_agent)

      result = @llm.stuff_todo(project: @project)

      assert_equal "Test error", result
    end

    should "call stream_proc on error" do
      # Mock IssueAgent to raise error
      mock_agent = mock("IssueAgent")
      mock_agent.expects(:suggest_stuff_todo).raises(StandardError.new("Test error"))

      RedmineAiHelper::Agents::IssueAgent.expects(:new).returns(mock_agent)

      streamed_content = []
      stream_proc = Proc.new { |content| streamed_content << content }

      result = @llm.stuff_todo(project: @project, stream_proc: stream_proc)

      assert_equal "Test error", result
      assert_includes streamed_content, "Test error"
    end
  end
end
