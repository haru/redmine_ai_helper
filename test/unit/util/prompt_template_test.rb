# frozen_string_literal: true

require_relative "../../test_helper"

class PromptTemplateTest < ActiveSupport::TestCase
  context "PromptTemplate" do
    context "initialize" do
      should "store template and input_variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name}",
          input_variables: ["name"]
        )
        assert_equal "Hello {name}", pt.template
        assert_equal ["name"], pt.input_variables
      end

      should "default input_variables to empty array" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(template: "Hello")
        assert_equal [], pt.input_variables
      end
    end

    context "format" do
      should "substitute single variable" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name}!",
          input_variables: ["name"]
        )
        assert_equal "Hello World!", pt.format(name: "World")
      end

      should "substitute multiple variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Goal: {goal}\nAgent list: {agent_list}",
          input_variables: ["goal", "agent_list"]
        )
        result = pt.format(goal: "Test goal", agent_list: "agent1, agent2")
        assert_equal "Goal: Test goal\nAgent list: agent1, agent2", result
      end

      should "return template as-is with no variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "You are an AI assistant.",
          input_variables: []
        )
        assert_equal "You are an AI assistant.", pt.format
      end

      should "not consume backslashes in replacement values" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Issue data: {issue}",
          input_variables: ["issue"]
        )
        json_with_backslashes = '{"path": "C:\\Users\\test", "newline": "line1\\nline2"}'
        result = pt.format(issue: json_with_backslashes)
        assert_equal "Issue data: #{json_with_backslashes}", result
      end

      should "handle JSON with special regex characters" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Data: {data}",
          input_variables: ["data"]
        )
        json = '{"regex": "\\d+", "price": "$100"}'
        result = pt.format(data: json)
        assert_equal "Data: #{json}", result
      end

      should "convert non-string values to string" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Count: {count}",
          input_variables: ["count"]
        )
        assert_equal "Count: 42", pt.format(count: 42)
      end

      should "substitute same variable multiple times" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "{name} says hello, {name}!",
          input_variables: ["name"]
        )
        assert_equal "Alice says hello, Alice!", pt.format(name: "Alice")
      end
    end

    context "load_from_path" do
      setup do
        @template_dir = File.dirname(__FILE__) + "/../../../assets/prompt_templates"
      end

      should "load a real prompt template file" do
        # Use the leader_agent/backstory template which has no input variables
        file_path = "#{@template_dir}/leader_agent/backstory.yml"
        pt = RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path)

        assert_instance_of RedmineAiHelper::Util::PromptTemplate, pt
        assert_includes pt.template, "leader agent"
        assert_equal [], pt.input_variables
      end

      should "load a template with input_variables" do
        # Use the leader_agent/goal template which has format_instructions variable
        file_path = "#{@template_dir}/leader_agent/goal.yml"
        pt = RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path)

        assert_instance_of RedmineAiHelper::Util::PromptTemplate, pt
        assert_includes pt.input_variables, "format_instructions"
      end

      should "format loaded template correctly" do
        file_path = "#{@template_dir}/leader_agent/goal.yml"
        pt = RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path)

        result = pt.format(format_instructions: "Output JSON only.")
        assert_includes result, "Output JSON only."
        refute_includes result, "{format_instructions}"
      end
    end
  end
end
