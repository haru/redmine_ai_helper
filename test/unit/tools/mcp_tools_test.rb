require_relative "../../test_helper"

class McpToolsTest < ActiveSupport::TestCase
  include RedmineAiHelper

  def setup
    # Create mock MCP client for testing
    @mock_client = create_mock_mcp_client
    @server_name = "test_server"
  end

  def teardown
    # Clean up dynamically generated classes after tests
    cleanup_dynamic_classes
  end

  context "McpTools" do
    should "generate tool class correctly" do
      tool_class = Tools::McpTools.generate_tool_class(
        mcp_server_name: @server_name,
        mcp_client: @mock_client
      )

      expected_class_name = "AiHelperMcpTestServerTools"
      assert_equal expected_class_name, tool_class.name
      assert tool_class < Tools::McpTools
    end

    should "avoid duplicate class generation" do
      tool_class1 = Tools::McpTools.generate_tool_class(
        mcp_server_name: @server_name,
        mcp_client: @mock_client
      )

      tool_class2 = Tools::McpTools.generate_tool_class(
        mcp_server_name: @server_name,
        mcp_client: @mock_client
      )

      assert_same tool_class1, tool_class2
    end

    should "handle mcp client method calls" do
      tool_class = Tools::McpTools.generate_tool_class(
        mcp_server_name: @server_name,
        mcp_client: @mock_client
      )

      tool_instance = tool_class.new

      # Verify generated function schema
      schemas = tool_class.function_schemas.to_openai_format
      assert schemas.length > 0, "Tool class should have function schemas"
      
      # Get actual function name from schema
      function_name = schemas.first.dig(:function, :name)
      assert_not_nil function_name, "Function should have a name"
      
      # Call tool using dynamically generated method name
      # langchainrb typically uses "ClassName__method_name" naming convention
      method_name = function_name.split("__").last || function_name
      
      result = tool_instance.send(method_name, "param" => "value")
      assert_not_nil result
      assert result.is_a?(String)
    end

    should "handle errors gracefully" do
      error_client = create_error_mock_client
      tool_class = Tools::McpTools.generate_tool_class(
        mcp_server_name: "error_server",
        mcp_client: error_client
      )

      tool_instance = tool_class.new

      # Verify generated function schema
      schemas = tool_class.function_schemas.to_openai_format
      if schemas.length > 0
        function_name = schemas.first.dig(:function, :name)
        method_name = function_name.split("__").last || function_name
        
        # Verify that errors don't cause crashes
        result = tool_instance.send(method_name, "param" => "value")
        assert result.include?("Error:")
      else
        # Skip if no schemas were generated
        skip "No function schemas were generated for error client"
      end
    end
  end

  private

  def create_mock_mcp_client
    mock_tool = Struct.new(:name, :description, :schema).new(
      "test_tool",
      "A test tool for testing purposes",
      {
        "type" => "object",
        "properties" => {
          "param" => {
            "type" => "string",
            "description" => "Test parameter"
          }
        },
        "required" => ["param"]
      }
    )

    mock_client = Object.new
    mock_client.define_singleton_method(:list_tools) do
      [mock_tool]
    end

    mock_client.define_singleton_method(:call_tool) do |tool_name, arguments|
      "Mock result for #{tool_name} with #{arguments.inspect}"
    end

    mock_client
  end

  def create_error_mock_client
    mock_tool = Struct.new(:name, :description, :schema).new(
      "test_tool",
      "A test tool that raises errors",
      {
        "type" => "object",
        "properties" => {
          "param" => {
            "type" => "string",
            "description" => "Test parameter"
          }
        },
        "required" => ["param"]
      }
    )

    mock_client = Object.new
    mock_client.define_singleton_method(:list_tools) do
      [mock_tool]
    end

    mock_client.define_singleton_method(:call_tool) do |tool_name, arguments|
      raise StandardError, "Mock error for testing"
    end

    mock_client
  end

  def cleanup_dynamic_classes
    Object.constants.each do |const|
      if const.to_s.start_with?('AiHelperMcp') && const.to_s.end_with?('Tools')
        begin
          Object.send(:remove_const, const)
        rescue NameError
          # Ignore if already deleted
        end
      end
    end
  end
end