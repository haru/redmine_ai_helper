require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/base_tools"

class BaseToolsTest < ActiveSupport::TestCase
  # Create test tool classes with various DSL patterns
  def setup
    # Simple tool with basic properties
    @simple_tool_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :greet, description: "Say hello to someone" do
        property :name, type: "string", description: "The name to greet", required: true
        property :formal, type: "boolean", description: "Whether to be formal", required: false
      end

      def greet(name:, formal: false)
        formal ? "Good day, #{name}." : "Hello, #{name}!"
      end
    end

    # Tool with array property
    @array_tool_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :process_items, description: "Process a list of items" do
        property :item_ids, type: "array", description: "List of item IDs", required: true do
          item type: "integer", description: "An item ID"
        end
      end

      def process_items(item_ids:)
        item_ids.map { |id| id * 2 }
      end
    end

    # Tool with nested object property
    @nested_tool_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :search, description: "Search with query object" do
        property :query, type: "object", description: "Search query", required: true do
          property :text, type: "string", description: "Search text", required: true
          property :limit, type: "integer", description: "Max results", required: false
        end
      end

      def search(query:)
        { results: [], query: query }
      end
    end

    # Tool with enum property
    @enum_tool_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :filter, description: "Filter by status" do
        property :status, type: "string", description: "Status filter", required: true, enum: ["active", "inactive"]
      end

      def filter(status:)
        status
      end
    end

    # Tool with multiple functions
    @multi_tool_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :action_one, description: "First action" do
        property :param_a, type: "string", description: "Parameter A", required: true
      end

      define_function :action_two, description: "Second action" do
        property :param_b, type: "integer", description: "Parameter B", required: true
      end

      def action_one(param_a:)
        "one: #{param_a}"
      end

      def action_two(param_b:)
        "two: #{param_b}"
      end
    end
  end

  context "BaseTools" do
    context "tool_classes" do
      should "generate RubyLLM::Tool subclasses for each define_function" do
        tool_classes = @simple_tool_class.tool_classes
        assert_equal 1, tool_classes.size
        assert tool_classes.first < RubyLLM::Tool, "Generated class should be a subclass of RubyLLM::Tool"
      end

      should "generate multiple tool classes for multiple define_functions" do
        tool_classes = @multi_tool_class.tool_classes
        assert_equal 2, tool_classes.size
        tool_classes.each do |tc|
          assert tc < RubyLLM::Tool
        end
      end

      should "not share tool_classes between different BaseTools subclasses" do
        simple_classes = @simple_tool_class.tool_classes
        multi_classes = @multi_tool_class.tool_classes
        assert_equal 1, simple_classes.size
        assert_equal 2, multi_classes.size
        assert_empty simple_classes & multi_classes
      end
    end

    context "tool execution via RubyLLM::Tool subclass" do
      should "delegate execute to the tools instance method" do
        tool_class = @simple_tool_class.tool_classes.first
        tool_instance = tool_class.new
        result = tool_instance.execute(name: "World")
        assert_equal "Hello, World!", result
      end

      should "delegate execute with optional params" do
        tool_class = @simple_tool_class.tool_classes.first
        tool_instance = tool_class.new
        result = tool_instance.execute(name: "Sir", formal: true)
        assert_equal "Good day, Sir.", result
      end

      should "delegate execute for array tool" do
        tool_class = @array_tool_class.tool_classes.first
        tool_instance = tool_class.new
        result = tool_instance.execute(item_ids: [1, 2, 3])
        assert_equal [2, 4, 6], result
      end
    end

    context "tool description" do
      should "set description on generated tool class" do
        tool_class = @simple_tool_class.tool_classes.first
        tool_instance = tool_class.new
        assert_equal "Say hello to someone", tool_instance.description
      end
    end

    context "tool parameters schema" do
      should "generate correct JSON schema for simple properties" do
        tool_class = @simple_tool_class.tool_classes.first
        tool_instance = tool_class.new
        schema = tool_instance.params_schema
        assert_equal "object", schema["type"]
        assert schema["properties"].key?("name")
        assert_equal "string", schema["properties"]["name"]["type"]
        assert_equal "The name to greet", schema["properties"]["name"]["description"]
        assert_includes schema["required"], "name"
        refute_includes schema["required"], "formal"
      end

      should "generate correct JSON schema for array properties" do
        tool_class = @array_tool_class.tool_classes.first
        tool_instance = tool_class.new
        schema = tool_instance.params_schema
        assert_equal "array", schema["properties"]["item_ids"]["type"]
        assert_equal "integer", schema["properties"]["item_ids"]["items"]["type"]
      end

      should "generate correct JSON schema for nested object properties" do
        tool_class = @nested_tool_class.tool_classes.first
        tool_instance = tool_class.new
        schema = tool_instance.params_schema
        query_schema = schema["properties"]["query"]
        assert_equal "object", query_schema["type"]
        assert query_schema["properties"].key?("text")
        assert_equal "string", query_schema["properties"]["text"]["type"]
        assert_includes query_schema["required"], "text"
      end

      should "generate correct JSON schema for enum properties" do
        tool_class = @enum_tool_class.tool_classes.first
        tool_instance = tool_class.new
        schema = tool_instance.params_schema
        assert_equal ["active", "inactive"], schema["properties"]["status"]["enum"]
      end
    end

    context "backward compatibility" do
      should "provide function_schemas with to_openai_format" do
        schemas = @simple_tool_class.function_schemas
        assert_respond_to schemas, :to_openai_format
        format = schemas.to_openai_format
        assert_equal 1, format.size
        assert_equal "function", format.first[:type]
        assert format.first[:function][:name].present?
        assert_equal "Say hello to someone", format.first[:function][:description]
        assert format.first[:function][:parameters].key?(:properties)
      end

      should "generate correct function names in openai format" do
        schemas = @multi_tool_class.function_schemas
        format = schemas.to_openai_format
        names = format.map { |f| f[:function][:name] }
        assert names.any? { |n| n.include?("action_one") }
        assert names.any? { |n| n.include?("action_two") }
      end
    end

    context "ParameterBuilder" do
      should "build properties from JSON schema (for MCP tools)" do
        json_schema = {
          "type" => "object",
          "properties" => {
            "city" => { "type" => "string", "description" => "City name" },
            "count" => { "type" => "integer", "description" => "Result count" },
          },
          "required" => ["city"],
        }

        builder = RedmineAiHelper::BaseTools::ParameterBuilder.new
        builder.build_properties_from_json(json_schema)

        assert_equal 2, builder.params.size
        city_param = builder.params.find { |p| p[:name] == :city }
        assert_equal "string", city_param[:type]
        assert_equal "City name", city_param[:description]
      end

      should "build nested object properties from JSON schema" do
        json_schema = {
          "type" => "object",
          "properties" => {
            "filter" => {
              "type" => "object",
              "description" => "Filter options",
              "properties" => {
                "key" => { "type" => "string", "description" => "Filter key" },
              },
            },
          },
        }

        builder = RedmineAiHelper::BaseTools::ParameterBuilder.new
        builder.build_properties_from_json(json_schema)

        filter_param = builder.params.find { |p| p[:name] == :filter }
        assert_equal "object", filter_param[:type]
        assert filter_param[:children].any? { |c| c[:name] == :key }
      end

      should "build array with items from JSON schema" do
        json_schema = {
          "type" => "object",
          "properties" => {
            "tags" => {
              "type" => "array",
              "description" => "Tag list",
              "items" => {
                "type" => "string",
                "description" => "A tag",
              },
            },
          },
        }

        builder = RedmineAiHelper::BaseTools::ParameterBuilder.new
        builder.build_properties_from_json(json_schema)

        tags_param = builder.params.find { |p| p[:name] == :tags }
        assert_equal "array", tags_param[:type]
        assert tags_param[:items]
        assert_equal "string", tags_param[:items][:type]
      end
    end

    context "accessible_project?" do
      should "return false for invisible project" do
        tools = @simple_tool_class.new
        project = mock("Project")
        project.stubs(:visible?).returns(false)
        refute tools.accessible_project?(project)
      end
    end
  end
end
