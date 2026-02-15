require_relative "../../test_helper"

class McpToolsTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @mock_client = create_mock_mcp_client
    @server_name = "test_server"
    # Clear cache between tests
    Tools::McpTools.instance_variable_set(:@mcp_tool_cache, nil)
  end

  context "McpTools" do
    should "return tool instances from MCP client" do
      tools = Tools::McpTools.generate_tool_classes(
        mcp_server_name: @server_name,
        mcp_client: @mock_client,
      )

      assert tools.is_a?(Array)
      assert_equal 2, tools.length
      assert_equal "test_tool", tools[0].name
      assert_equal "A test tool", tools[0].description
      assert_equal "other_tool", tools[1].name
      assert_equal "Another tool", tools[1].description
    end

    should "cache tool instances per server name" do
      tools1 = Tools::McpTools.generate_tool_classes(
        mcp_server_name: @server_name,
        mcp_client: @mock_client,
      )

      tools2 = Tools::McpTools.generate_tool_classes(
        mcp_server_name: @server_name,
        mcp_client: @mock_client,
      )

      assert_same tools1, tools2
    end

    should "cache separately for different servers" do
      other_client = create_mock_mcp_client(tool_name: "different_tool", tool_description: "Different tool")

      tools1 = Tools::McpTools.generate_tool_classes(
        mcp_server_name: "server1",
        mcp_client: @mock_client,
      )

      tools2 = Tools::McpTools.generate_tool_classes(
        mcp_server_name: "server2",
        mcp_client: other_client,
      )

      assert_not_same tools1, tools2
    end

    should "return empty array when client.tools raises error" do
      error_client = Object.new
      error_client.define_singleton_method(:tools) do
        raise StandardError, "Connection failed"
      end

      tools = Tools::McpTools.generate_tool_classes(
        mcp_server_name: "error_server",
        mcp_client: error_client,
      )

      assert_equal [], tools
    end
  end

  private

  def create_mock_mcp_client(tool_name: "test_tool", tool_description: "A test tool")
    mock_tool1 = Struct.new(:name, :description).new(tool_name, tool_description)
    mock_tool2 = Struct.new(:name, :description).new("other_tool", "Another tool")

    mock_client = Object.new
    mock_client.define_singleton_method(:tools) do
      [mock_tool1, mock_tool2]
    end

    mock_client
  end
end
