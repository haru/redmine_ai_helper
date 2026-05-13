# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/mcp/tool_adapter"

class MCPToolAdapterTest < ActiveSupport::TestCase
  def setup
    @simple_tools_class = Class.new(RedmineAiHelper::BaseTools) do
      define_function :search_widgets, description: "Search for widgets by name" do
        property :name, type: "string", description: "Widget name to search", required: true
        property :limit, type: "integer", description: "Maximum results", required: false
      end

      def search_widgets(name:, limit: 10) # rubocop:disable Lint/UnusedMethodArgument
        [ { id: 1, name: name } ]
      end
    end

    @ruby_tool_class = @simple_tools_class.tool_classes.first
  end

  context "MCPToolAdapter.adapt" do
    should "return an MCP::Tool subclass" do
      mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(@ruby_tool_class)

      assert_operator mcp_tool, :<, MCP::Tool
    end

    should "map the tool name correctly" do
      mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(@ruby_tool_class)

      assert_equal "search_widgets", mcp_tool.name_value
    end

    should "map the tool description correctly" do
      mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(@ruby_tool_class)

      assert_equal "Search for widgets by name", mcp_tool.description_value
    end

    should "map the input_schema with required properties" do
      mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(@ruby_tool_class)
      schema = mcp_tool.input_schema_value.to_h

      assert_equal "object", schema[:type].to_s
      assert schema[:properties].key?(:name) || schema[:properties].key?("name"),
             "input schema should contain 'name' property"
    end

    context "call wrapping" do
      setup do
        @mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(@ruby_tool_class)
      end

      should "return isError false on success" do
        result = @mcp_tool.call(name: "gizmo")

        assert_equal false, result[:isError]
      end

      should "return content array with type text on success" do
        result = @mcp_tool.call(name: "gizmo")

        assert_kind_of Array, result[:content]
        assert_equal "text", result[:content].first[:type]
      end

      should "return JSON-encoded result in text content" do
        result = @mcp_tool.call(name: "gizmo")
        parsed = JSON.parse(result[:content].first[:text])

        assert_kind_of Array, parsed
        assert_equal "gizmo", parsed.first["name"]
      end

      should "return isError true when tool raises an exception" do
        error_tools_class = Class.new(RedmineAiHelper::BaseTools) do
          define_function :explode, description: "Always raises" do
            property :dummy, type: "string", description: "Dummy", required: false
          end

          def explode(dummy: nil) # rubocop:disable Lint/UnusedMethodArgument
            raise "Something went wrong"
          end
        end

        error_tool = error_tools_class.tool_classes.first
        mcp_tool = RedmineAiHelper::Mcp::MCPToolAdapter.adapt(error_tool)
        result = mcp_tool.call

        assert_equal true, result[:isError]
        assert_includes result[:content].first[:text], "Something went wrong"
      end
    end
  end
end
