# frozen_string_literal: true

require_relative "../../test_helper"
require "tmpdir"

class PromptTemplateTest < ActiveSupport::TestCase
  context "PromptTemplate" do
    context "initialize" do
      should "store template and input_variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name}",
          input_variables: [ "name" ]
        )

        assert_equal "Hello {name}", pt.template
        assert_equal [ "name" ], pt.input_variables
      end

      should "reject input_variables that is not an Array" do
        [ "name", nil, { a: 1 }, 5 ].each do |bad|
          error = assert_raises(ArgumentError) do
            RedmineAiHelper::Util::PromptTemplate.new(template: "x", input_variables: bad)
          end
          assert_includes error.message, bad.class.name
        end
      end

      should "reject input_variables elements that are not String or Symbol" do
        error = assert_raises(ArgumentError) do
          RedmineAiHelper::Util::PromptTemplate.new(template: "x", input_variables: [ "a", 1 ])
        end
        assert_includes error.message, "Integer"
      end

      should "normalize Symbol input_variables to strings" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(template: "x", input_variables: [ :name, "other" ])

        assert_equal [ "name", "other" ], pt.input_variables
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
          input_variables: [ "name" ]
        )

        assert_equal "Hello World!", pt.format(name: "World")
      end

      should "substitute multiple variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Goal: {goal}\nAgent list: {agent_list}",
          input_variables: [ "goal", "agent_list" ]
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
          input_variables: [ "issue" ]
        )
        json_with_backslashes = '{"path": "C:\\Users\\test", "newline": "line1\\nline2"}'
        result = pt.format(issue: json_with_backslashes)

        assert_equal "Issue data: #{json_with_backslashes}", result
      end

      should "handle JSON with special regex characters" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Data: {data}",
          input_variables: [ "data" ]
        )
        json = '{"regex": "\\d+", "price": "$100"}'
        result = pt.format(data: json)

        assert_equal "Data: #{json}", result
      end

      should "convert non-string values to string" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Count: {count}",
          input_variables: [ "count" ]
        )

        assert_equal "Count: 42", pt.format(count: 42)
      end

      should "substitute same variable multiple times" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "{name} says hello, {name}!",
          input_variables: [ "name" ]
        )

        assert_equal "Alice says hello, Alice!", pt.format(name: "Alice")
      end

      should "raise ArgumentError naming a missing variable" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name} {missing}",
          input_variables: [ "name", "missing" ]
        )

        error = assert_raises(ArgumentError) { pt.format(name: "x") }
        assert_includes error.message, "missing"
      end

      should "raise ArgumentError naming an unknown variable" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name}",
          input_variables: [ "name" ]
        )

        error = assert_raises(ArgumentError) { pt.format(name: "x", extra: "y") }
        assert_includes error.message, "extra"
      end

      should "raise one ArgumentError reporting missing and unknown variables" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "Hello {name} {missing}",
          input_variables: [ "name", "missing" ]
        )

        error = assert_raises(ArgumentError) { pt.format(name: "x", extra: "y") }
        assert_equal "Missing prompt variables: missing; unknown prompt variables: extra", error.message
      end

      should "insert backslash sequences literally when variables match exactly" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "A {a} B {b}",
          input_variables: [ "a", "b" ]
        )

        assert_equal 'A \\1 B \\\\', pt.format(a: '\\1', b: "\\\\")
      end

      should "treat nil and empty string values as given" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "[{a}][{b}]",
          input_variables: [ "a", "b" ]
        )

        assert_equal "[][]", pt.format(a: nil, b: "")
      end

      should "return the body unchanged for empty declarations without arguments" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(template: "Body", input_variables: [])

        assert_equal "Body", pt.format
      end

      should "raise ArgumentError when a variable is given to a template that declares none" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(template: "Body", input_variables: [])

        error = assert_raises(ArgumentError) { pt.format(foo: "x") }
        assert_includes error.message, "foo"
      end

      should "match symbol keys against string declarations and symbol declarations" do
        string_decl = RedmineAiHelper::Util::PromptTemplate.new(template: "{a}", input_variables: [ "a" ])
        symbol_decl = RedmineAiHelper::Util::PromptTemplate.new(template: "{a}", input_variables: [ :a ])

        assert_equal "1", string_decl.format(a: 1)
        assert_equal "1", symbol_decl.format(a: 1)
      end

      should "not return a partially substituted string or alter the template on failure" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "{a} {b}",
          input_variables: [ "a", "b" ]
        )

        assert_raises(ArgumentError) { pt.format(a: "x") }
        assert_equal "{a} {b}", pt.template
      end
    end

    context "validation failure logging" do
      should "log the path and variable names but keep the path out of the error message" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(
          template: "{a}",
          input_variables: [ "a" ],
          path: "/secret/dir/t.yml"
        )
        logged = []
        logger = mock("logger")
        logger.expects(:error).with { |m| logged << m }
        pt.stubs(:ai_helper_logger).returns(logger)

        error = assert_raises(ArgumentError) { pt.format(b: "x") }

        assert_equal 1, logged.size
        assert_includes logged.first, "/secret/dir/t.yml"
        assert_includes logged.first, "a"
        assert_includes logged.first, "b"
        assert_not_includes error.message, "/secret/dir"
      end

      should "omit the path item when the template has no path" do
        pt = RedmineAiHelper::Util::PromptTemplate.new(template: "{a}", input_variables: [ "a" ])
        logged = []
        logger = mock("logger")
        logger.expects(:error).with { |m| logged << m }
        pt.stubs(:ai_helper_logger).returns(logger)

        assert_raises(ArgumentError) { pt.format(b: "x") }

        assert_equal 1, logged.size
        assert_not_includes logged.first.downcase, "path"
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

      should "expose the file path of a loaded template" do
        Dir.mktmpdir do |dir|
          file_path = File.join(dir, "t.yml")
          File.write(file_path, "template: \"Hi\"\ninput_variables: []\n")
          pt = RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path)

          assert_equal file_path, pt.path
        end
      end

      should "have a nil path when created directly" do
        assert_nil RedmineAiHelper::Util::PromptTemplate.new(template: "Hi").path
      end

      should "raise ArgumentError when a YAML file declares non-array input_variables" do
        Dir.mktmpdir do |dir|
          file_path = File.join(dir, "t.yml")
          File.write(file_path, "template: \"Hi\"\ninput_variables: name\n")

          assert_raises(ArgumentError) { RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path) }
        end
      end

      should "raise ArgumentError when a YAML file declares non-string input_variables elements" do
        Dir.mktmpdir do |dir|
          file_path = File.join(dir, "t.yml")
          File.write(file_path, "template: \"Hi\"\ninput_variables: [1]\n")

          assert_raises(ArgumentError) { RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path) }
        end
      end

      should "default to empty input_variables when the YAML file has no such key" do
        Dir.mktmpdir do |dir|
          file_path = File.join(dir, "t.yml")
          File.write(file_path, "template: \"Hi\"\n")

          assert_equal [], RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path).input_variables
        end
      end

      should "format loaded template correctly" do
        file_path = "#{@template_dir}/leader_agent/goal.yml"
        pt = RedmineAiHelper::Util::PromptTemplate.load_from_path(file_path)

        result = pt.format(format_instructions: "Output JSON only.")

        assert_includes result, "Output JSON only."
        assert_not_includes result, "{format_instructions}"
      end
    end
  end
end
