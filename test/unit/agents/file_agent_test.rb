require File.expand_path("../../../test_helper", __FILE__)

class FileAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @agent = RedmineAiHelper::Agents::FileAgent.new
  end

  context "FileAgent" do
    should "have correct backstory" do
      backstory = @agent.backstory
      assert_not_nil backstory
      assert backstory.is_a?(String)
      assert backstory.include?("file analysis agent")
    end

    should "have correct available_tool_providers" do
      assert_equal [RedmineAiHelper::Tools::FileTools], @agent.available_tool_providers
    end

    should "have correct available_tool_classes" do
      tool_classes = @agent.available_tool_classes
      RedmineAiHelper::Tools::FileTools.tool_classes.each do |tc|
        assert_includes tool_classes, tc
      end
    end

    should "be registered in AgentList" do
      agent_list = RedmineAiHelper::AgentList.instance
      agent_info = agent_list.find_agent("file_agent")
      assert_not_nil agent_info, "FileAgent should be registered in AgentList"
      assert_equal "RedmineAiHelper::Agents::FileAgent", agent_info[:class]
    end

    should "appear in list_agents" do
      agents = RedmineAiHelper::AgentList.instance.list_agents
      file_agent_entry = agents.find { |a| a[:agent_name] == "file_agent" }
      assert_not_nil file_agent_entry, "FileAgent should appear in list_agents"
      assert file_agent_entry[:backstory].is_a?(String)
    end
  end
end
