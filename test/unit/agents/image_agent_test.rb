require File.expand_path("../../../test_helper", __FILE__)

class ImageAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @agent = RedmineAiHelper::Agents::ImageAgent.new
  end

  context "ImageAgent" do
    should "have correct backstory" do
      backstory = @agent.backstory
      assert_not_nil backstory
      assert backstory.is_a?(String)
      assert backstory.include?("image analysis agent")
    end

    should "have correct available_tool_providers" do
      assert_equal [RedmineAiHelper::Tools::ImageTools], @agent.available_tool_providers
    end

    should "have correct available_tool_classes" do
      tool_classes = @agent.available_tool_classes
      RedmineAiHelper::Tools::ImageTools.tool_classes.each do |tc|
        assert_includes tool_classes, tc
      end
    end

    should "be registered in AgentList" do
      agent_list = RedmineAiHelper::AgentList.instance
      agent_info = agent_list.find_agent("image_agent")
      assert_not_nil agent_info, "ImageAgent should be registered in AgentList"
      assert_equal "RedmineAiHelper::Agents::ImageAgent", agent_info[:class]
    end

    should "appear in list_agents" do
      agents = RedmineAiHelper::AgentList.instance.list_agents
      image_agent_entry = agents.find { |a| a[:agent_name] == "image_agent" }
      assert_not_nil image_agent_entry, "ImageAgent should appear in list_agents"
      assert image_agent_entry[:backstory].is_a?(String)
    end
  end
end
