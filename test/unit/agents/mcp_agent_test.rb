require_relative "../../test_helper"

class McpAgentTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @agent = Agents::McpAgent.new
  end

  context "McpAgent" do
    should "return correct role" do
      assert_equal "mcp_agent", @agent.role
    end

    should "be disabled by default" do
      assert_equal false, @agent.enabled?
    end

    should "return backstory" do
      backstory = @agent.backstory
      assert_not_nil backstory
      assert backstory.is_a?(String)
    end
  end
end