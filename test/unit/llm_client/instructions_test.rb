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

    should "default variable to an empty string" do
      instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "F")

      assert_equal "", instructions.variable
      assert_not instructions.variable?
    end

    should "report whether variable has content" do
      assert RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: "V").variable?
    end

    should "raise ArgumentError when fixed is nil, empty or not a String" do
      [ nil, "", :fixed ].each do |fixed|
        assert_raises(ArgumentError) { RedmineAiHelper::LlmClient::Instructions.new(fixed: fixed, variable: "V") }
      end
    end

    should "raise ArgumentError when variable is not a String" do
      assert_raises(ArgumentError) { RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: nil) }
    end

    context "coerce" do
      should "return nil for nil" do
        assert_nil RedmineAiHelper::LlmClient::Instructions.coerce(nil)
      end

      should "return Instructions unchanged" do
        instructions = RedmineAiHelper::LlmClient::Instructions.new(fixed: "F", variable: "V")

        assert_same instructions, RedmineAiHelper::LlmClient::Instructions.coerce(instructions)
      end

      should "wrap a String as the fixed part" do
        instructions = RedmineAiHelper::LlmClient::Instructions.coerce("plain")

        assert_equal "plain", instructions.fixed
        assert_equal "", instructions.variable
      end

      should "raise ArgumentError for any other type" do
        assert_raises(ArgumentError) { RedmineAiHelper::LlmClient::Instructions.coerce({ text: "plain" }) }
      end
    end
  end
end
