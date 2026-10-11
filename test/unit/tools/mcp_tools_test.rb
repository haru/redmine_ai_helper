require_relative "../../test_helper"

class McpToolsTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    @mock_client = create_mock_mcp_client
    @server_name = "test_server"
  end

  context "McpTools" do
    should "return tool instances from MCP client" do
      tools = Tools::McpTools.generate_tool_classes(
        mcp_server_name: @server_name,
        mcp_client: @mock_client
      )

      assert_kind_of Array, tools
      assert_equal 2, tools.length
      assert_equal "test_tool", tools[0].name
      assert_equal "A test tool", tools[0].description
      assert_equal "other_tool", tools[1].name
      assert_equal "Another tool", tools[1].description
    end

    should "raise connection errors instead of returning an empty list" do
      error_client = Object.new
      error_client.define_singleton_method(:tools) do
        raise RubyLLM::MCP::Error, "connection refused"
      end

      error = assert_raises(RubyLLM::MCP::Error) do
        Tools::McpTools.generate_tool_classes(mcp_server_name: "unreachable_server", mcp_client: error_client)
      end
      assert_equal "connection refused", error.message
    end

    should "not cache a failed lookup so the next call can succeed" do
      calls = 0
      client = Object.new
      client.define_singleton_method(:tools) do
        calls += 1
        raise StandardError, "Connection failed" if calls == 1

        [ :tool ]
      end

      assert_raises(StandardError) { Tools::McpTools.generate_tool_classes(mcp_server_name: "s", mcp_client: client) }
      assert_equal [ :tool ], Tools::McpTools.generate_tool_classes(mcp_server_name: "s", mcp_client: client)
    end
  end

  private

  def create_mock_mcp_client(tool_name: "test_tool", tool_description: "A test tool")
    mock_tool1 = Struct.new(:name, :description).new(tool_name, tool_description)
    mock_tool2 = Struct.new(:name, :description).new("other_tool", "Another tool")

    mock_client = Object.new
    mock_client.define_singleton_method(:tools) do
      [ mock_tool1, mock_tool2 ]
    end

    mock_client
  end
end
