require_relative "../../../test_helper"
require "redmine_ai_helper/llm"

class RedmineAiHelper::LlmIssueSummaryTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations

  context "#issue_summary" do
    setup do
      @previous_user = User.current
      @issue = Issue.find(1)
      User.current = User.find(1)
    end

    teardown do
      User.current = @previous_user
    end

    should "return the agent's answer on success" do
      agent = mock("IssueReadAgent")
      RedmineAiHelper::Agents::IssueReadAgent.stubs(:new).returns(agent)
      agent.stubs(:issue_summary).returns("The summary")

      assert_equal "The summary", RedmineAiHelper::Llm.new.issue_summary(issue: @issue)
    end

    should "re-raise generation errors instead of turning them into the summary text" do
      agent = mock("IssueReadAgent")
      RedmineAiHelper::Agents::IssueReadAgent.stubs(:new).returns(agent)
      agent.stubs(:issue_summary).raises(StandardError, "prompt template missing")

      assert_raises(StandardError) do
        RedmineAiHelper::Llm.new.issue_summary(issue: @issue)
      end
    end

    should "return Permission denied for a non-visible issue" do
      Issue.any_instance.stubs(:visible?).returns(false)

      assert_equal "Permission denied", RedmineAiHelper::Llm.new.issue_summary(issue: @issue)
    end
  end
end
