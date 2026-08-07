require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/issue_update_agent"

class RedmineAiHelper::Agents::IssueUpdateAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations

  context "IssueUpdateAgent" do
    setup do
      @project = Project.find(1)
      @user = User.find(1)
      @langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: "Test input for Langfuse")
      @agent = RedmineAiHelper::Agents::IssueUpdateAgent.new(project: @project, langfuse: @langfuse)
    end

    should "declare itself as the sole agent that actually creates and updates issues (US1)" do
      backstory = @agent.backstory

      assert_match(/the only agent that (actually )?creates? and updates? .*issues/i, backstory)
    end

    should "declare itself as the sole agent that actually creates and updates issues in Japanese (US1)" do
      backstory = I18n.with_locale(:ja) { @agent.backstory }

      assert_match(/実際に.*作成.*更新.*(行う|できる)/, backstory)
    end
  end
end
