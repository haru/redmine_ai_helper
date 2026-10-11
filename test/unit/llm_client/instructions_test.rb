require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/llm_client/instructions"

class RedmineAiHelper::LlmClient::InstructionsTest < ActiveSupport::TestCase
  context "Instructions" do
    should "expose fixed and variable" do
      instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: "V")
      assert_equal "F", instructions.fixed
      assert_equal "V", instructions.variable
    end

    should "join fixed and variable with a blank line in to_s" do
      instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: "V")
      assert_equal "F\n\nV", instructions.to_s
    end

    should "return only fixed in to_s when variable is empty" do
      instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: "")
      assert_equal "F", instructions.to_s
    end
  end
end
