require File.expand_path("../../../test_helper", __FILE__)

class DmsfAgentTest < ActiveSupport::TestCase
  test "remains disabled when the DMSF plugin is absent" do
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(nil)
    RedmineAiHelper::Tools::DmsfTools.stubs(:enabled?).returns(false)

    assert_equal false, RedmineAiHelper::Agents::DmsfAgent.new.enabled?
  end

  test "is enabled only when both DMSF and attachment opt-in are present" do
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(nil)
    RedmineAiHelper::Tools::DmsfTools.stubs(:enabled?).returns(true)

    agent = RedmineAiHelper::Agents::DmsfAgent.new
    assert agent.enabled?
    assert_equal [ RedmineAiHelper::Tools::DmsfTools ], agent.available_tool_providers
    assert_equal 2, agent.available_tool_classes.size
    assert_includes agent.backstory, "DMSF document agent"
  end
end
