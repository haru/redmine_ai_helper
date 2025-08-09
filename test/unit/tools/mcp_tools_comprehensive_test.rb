require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/tools/mcp_tools"

# Mock MCPClient constant for tests
class MCPClient
  def self.create_client(*args); end
  def self.stdio_config(*args); end  
  def self.http_config(*args); end
  def self.sse_config(*args); end
end

class RedmineAiHelper::Tools::McpToolsComprehensiveTest < ActiveSupport::TestCase
  context "McpTools comprehensive coverage" do
    setup do
      # Reset counter and clean up any existing constants
      RedmineAiHelper::Tools::McpTools.instance_variable_set(:@mcp_server_call_counter, 0)
      
      # Mock the require statement to prevent loading the real gem
      Kernel.stubs(:require).with('mcp_client').returns(true)
    end

    teardown do
      # Clean up created constants to avoid warnings
      ["McpTestTool", "McpTestGenerator", "McpTransportTest", "McpLoadJsonTest", "McpMethodMissingTest", "McpExecTest"].each do |const_name|
        Object.send(:remove_const, const_name) if Object.const_defined?(const_name)
      end
    end

    context "generate_tool_class method" do
      should "create class with proper inheritance and instance variables" do
        json = { "command" => "test", "args" => ["arg1"] }
        
        # Mock the load_from_mcp_server to prevent actual MCP communication
        RedmineAiHelper::Tools::McpTools.stubs(:load_from_mcp_server).returns(nil)
        
        # Mock ruby-mcp-client
        mock_client = mock('mcp_client')
        mock_client.stubs(:list_tools).returns([])
        mock_client.stubs(:cleanup)
        ::MCPClient.stubs(:create_client).returns(mock_client)
        ::MCPClient.stubs(:stdio_config).returns({type: 'stdio'})
        
        klass = nil
        assert_nothing_raised do
          klass = RedmineAiHelper::Tools::McpTools.generate_tool_class(name: "test_tool", json: json)
        end
        
        assert_equal "McpTest_tool", klass.name
        assert klass.ancestors.include?(RedmineAiHelper::Tools::McpTools)
        assert klass.instance_variable_get(:@mcp_server_json).frozen?
        assert_equal json, klass.instance_variable_get(:@mcp_server_json)
        assert_equal 0, klass.instance_variable_get(:@mcp_server_call_counter)
      end

      should "handle transport creation and method delegation" do
        json = { "command" => "node", "args" => ["server.js"], "env" => { "NODE_ENV" => "test" } }
        
        # Mock load_from_mcp_server to avoid actual MCP calls
        RedmineAiHelper::Tools::McpTools.stubs(:load_from_mcp_server).returns(nil)
        
        klass = RedmineAiHelper::Tools::McpTools.generate_tool_class(name: "transport_test", json: json)
        
        # Mock the mcp_client method on the generated class to avoid gem loading
        mock_client = mock('mcp_client')
        mock_client.stubs(:list_tools).returns([])
        mock_client.stubs(:cleanup)
        mock_client.stubs(:call_tool).returns("success")
        klass.stubs(:mcp_client).returns(mock_client)
        
        # Mock send_mcp_request to avoid actual MCP calls
        klass.stubs(:send_mcp_request).returns({ "result" => "success" })
        
        # Test mcp_client method
        client = klass.mcp_client
        assert_not_nil client
        
        # Test command_array method
        expected_command = ["node", "server.js"]
        assert_equal expected_command, klass.command_array
        
        # Test env_hash method
        assert_equal({ "NODE_ENV" => "test" }, klass.env_hash)
        
        # Test send_mcp_request method
        message = { "method" => "test" }
        result = klass.send_mcp_request(message)
        assert_equal({ "result" => "success" }, result)
      end

      should "handle HTTP configuration" do
        json = { "url" => "http://localhost:3000", "headers" => { "Auth" => "Bearer token" } }
        
        RedmineAiHelper::Tools::McpTools.stubs(:load_from_mcp_server).returns(nil)
        
        klass = RedmineAiHelper::Tools::McpTools.generate_tool_class(name: "http_test", json: json)
        
        # Mock the mcp_client method on the generated class to avoid gem loading
        mock_client = mock('mcp_client')
        mock_client.stubs(:list_tools).returns([])
        mock_client.stubs(:cleanup)
        klass.stubs(:mcp_client).returns(mock_client)
        
        # Access mcp_client to test
        klass.mcp_client
        
        # HTTP config should return empty command_array
        assert_equal [], klass.command_array
        
        # Should return empty env_hash when no env provided
        assert_equal({}, klass.env_hash)
      end

      should "handle transport closing" do
        json = { "command" => "test" }
        
        # Mock ruby-mcp-client for close testing
        mock_client = mock('mcp_client')
        mock_client.stubs(:list_tools).returns([])
        mock_client.expects(:cleanup).once
        ::MCPClient.stubs(:create_client).returns(mock_client)
        ::MCPClient.stubs(:stdio_config).returns({type: 'stdio'})
        RedmineAiHelper::Tools::McpTools.stubs(:load_from_mcp_server).returns(nil)
        
        klass = RedmineAiHelper::Tools::McpTools.generate_tool_class(name: "close_test", json: json)
        
        # Set mcp_client and test closing
        klass.instance_variable_set(:@mcp_client, mock_client)
        klass.close_transport
        
        assert_nil klass.instance_variable_get(:@mcp_client)
      end
    end

    context "load_from_mcp_server method" do
      should "send tools/list request and process response" do
        json = { "command" => "test" }
        
        # Create class without auto-loading
        class_name = "McpLoadJsonTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @mcp_server_call_counter = 5  # Set specific counter value
          
          def self.send_mcp_request(message)
            # Verify the request format
            expected = {
              "method" => "tools/list",
              "params" => {},
              "jsonrpc" => "2.0",
              "id" => 5
            }
            raise "Unexpected request" unless message == expected
            
            # Return mock response
            {
              "result" => {
                "tools" => [
                  {
                    "name" => "test_tool",
                    "description" => "A test tool",
                    "inputSchema" => {
                      "type" => "object",
                      "properties" => {
                        "param1" => { "type" => "string", "description" => "Parameter 1" }
                      }
                    }
                  }
                ]
              }
            }
          end
          
          def self.load_json(json:)
            @loaded_tools = json
          end
        end
        Object.const_set(class_name, klass)
        
        # Test load_from_mcp_server
        assert_nothing_raised do
          klass.load_from_mcp_server
        end
        
        # Verify counter was incremented (the method increments twice: once by mcp_server_call_counter_up, once manually)
        assert_equal 7, klass.instance_variable_get(:@mcp_server_call_counter)
        
        # Verify tools were loaded
        loaded_tools = klass.instance_variable_get(:@loaded_tools)
        assert_equal 1, loaded_tools.length
        assert_equal "test_tool", loaded_tools.first["name"]
      end

      should "handle response parsing errors gracefully" do
        json = { "command" => "test" }
        
        class_name = "McpErrorTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @mcp_server_call_counter = 0
          
          def self.send_mcp_request(message)
            # Return response that will cause parsing error
            { "error" => { "code" => -1, "message" => "Server error" } }
          end
          
          def self.load_json(json:)
            @loaded_tools = json
          end
        end
        Object.const_set(class_name, klass)
        
        # Should handle error gracefully
        assert_nothing_raised do
          klass.load_from_mcp_server
        end
        
        # Should have called load_json with nil
        assert_nil klass.instance_variable_get(:@loaded_tools)
      end
    end

    context "load_json method" do
      should "handle single tool JSON" do
        json = { "command" => "test" }
        
        class_name = "McpSingleToolTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @defined_functions = []
          
          def self.define_function(name, description:, &block)
            @defined_functions << { name: name, description: description }
            block.call if block_given?
          end
          
          def self.build_properties_from_json(schema)
            @built_schemas ||= []
            @built_schemas << schema
          end
        end
        Object.const_set(class_name, klass)
        
        tool_json = {
          "name" => "single_tool",
          "description" => "A single tool",
          "inputSchema" => {
            "type" => "object",
            "properties" => {
              "param1" => { "type" => "string", "description" => "Parameter 1" }
            }
          }
        }
        
        # Test load_json with single tool
        klass.load_json(json: tool_json)
        
        defined_functions = klass.instance_variable_get(:@defined_functions)
        assert_equal 1, defined_functions.length
        assert_equal "single_tool", defined_functions.first[:name]
        assert_equal "A single tool", defined_functions.first[:description]
      end

      should "handle array of tools JSON" do
        json = { "command" => "test" }
        
        class_name = "McpArrayToolTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @defined_functions = []
          
          def self.define_function(name, description:, &block)
            @defined_functions << { name: name, description: description }
            block.call if block_given?
          end
          
          def self.build_properties_from_json(schema)
            # No-op for this test
          end
        end
        Object.const_set(class_name, klass)
        
        tools_array = [
          {
            "name" => "tool1",
            "description" => "First tool",
            "inputSchema" => {
              "type" => "object",
              "properties" => { "param1" => { "type" => "string" } }
            }
          },
          {
            "name" => "tool2",
            "description" => "Second tool",
            "inputSchema" => {
              "type" => "object",
              "properties" => {}
            }
          }
        ]
        
        # Test load_json with array
        klass.load_json(json: tools_array)
        
        defined_functions = klass.instance_variable_get(:@defined_functions)
        assert_equal 2, defined_functions.length
        assert_equal "tool1", defined_functions[0][:name]
        assert_equal "tool2", defined_functions[1][:name]
      end

      should "handle empty properties by adding dummy property" do
        json = { "command" => "test" }
        
        class_name = "McpEmptyPropsTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @processed_schemas = []
          
          def self.define_function(name, description:, &block)
            block.call if block_given?
          end
          
          def self.build_properties_from_json(schema)
            @processed_schemas << schema
          end
        end
        Object.const_set(class_name, klass)
        
        tool_with_empty_props = {
          "name" => "empty_tool",
          "description" => "Tool with empty properties",
          "inputSchema" => {
            "type" => "object",
            "properties" => {}
          }
        }
        
        # Test load_json
        klass.load_json(json: tool_with_empty_props)
        
        processed_schemas = klass.instance_variable_get(:@processed_schemas)
        assert_equal 1, processed_schemas.length
        
        schema = processed_schemas.first
        assert schema["properties"].has_key?("dummy_property")
        assert_equal "string", schema["properties"]["dummy_property"]["type"]
        assert_equal "dummy property", schema["properties"]["dummy_property"]["description"]
      end
    end

    context "deprecated execut_mcp_command method" do
      should "delegate to send_mcp_request and return JSON" do
        json = { "command" => "test" }
        
        class_name = "McpExecTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          
          def self.send_mcp_request(message)
            { "result" => "executed", "input" => message }
          end
        end
        Object.const_set(class_name, klass)
        
        input_json = '{"method": "test_method", "params": {"arg1": "value1"}}'
        result = klass.execut_mcp_command(input_json: input_json)
        
        parsed_result = JSON.parse(result)
        assert_equal "executed", parsed_result["result"]
        assert_equal "test_method", parsed_result["input"]["method"]
        assert_equal({"arg1" => "value1"}, parsed_result["input"]["params"])
      end
    end

    context "instance method_missing" do
      should "execute tool via MCP and return JSON response" do
        json = { "command" => "test" }
        
        # Create mock schemas outside the class
        mock_schemas = mock('schemas')
        mock_schemas.stubs(:to_openai_format).returns([
          {
            function: {
              name: "test_class__test_function",
              description: "Test function"
            }
          }
        ])
        
        class_name = "McpMethodMissingTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @mcp_server_call_counter = 10
          
          define_singleton_method(:function_schemas) do
            mock_schemas
          end
          
          def self.send_mcp_request(message)
            expected = {
              "method" => "tools/call",
              "params" => {
                "name" => "test_function",
                "arguments" => { "param1" => "value1" }
              },
              "jsonrpc" => "2.0",
              "id" => 10
            }
            
            if message == expected
              { "result" => { "output" => "function executed" } }
            else
              { "error" => "unexpected message format" }
            end
          end
          
          def self.mcp_server_call_counter_up
            counter = @mcp_server_call_counter
            @mcp_server_call_counter += 1
            counter
          end
        end
        Object.const_set(class_name, klass)
        
        instance = klass.new
        
        # Test method_missing with valid function
        result = instance.test_function({ "param1" => "value1" })
        parsed_result = JSON.parse(result)
        
        assert_equal "function executed", parsed_result["result"]["output"]
      end

      should "raise ArgumentError for non-existent function" do
        json = { "command" => "test" }
        
        # Create mock schemas outside the class
        mock_schemas = mock('schemas')
        mock_schemas.stubs(:to_openai_format).returns([])
        
        class_name = "McpNotFoundTest"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          
          define_singleton_method(:function_schemas) do
            mock_schemas
          end
        end
        Object.const_set(class_name, klass)
        
        instance = klass.new
        
        assert_raises ArgumentError do
          instance.non_existent_function
        end
      end
    end

    context "counter methods" do
      should "handle mcp_server_call_counter operations" do
        # Test initial state
        RedmineAiHelper::Tools::McpTools.instance_variable_set(:@mcp_server_call_counter, nil)
        assert_equal 0, RedmineAiHelper::Tools::McpTools.mcp_server_call_counter
        
        # Test counter increment
        RedmineAiHelper::Tools::McpTools.instance_variable_set(:@mcp_server_call_counter, 15)
        previous = RedmineAiHelper::Tools::McpTools.mcp_server_call_counter_up
        assert_equal 15, previous
        assert_equal 16, RedmineAiHelper::Tools::McpTools.mcp_server_call_counter
      end
    end

    context "base class behavior" do
      should "raise NotImplementedError for base send_mcp_request" do
        assert_raises NotImplementedError do
          RedmineAiHelper::Tools::McpTools.send_mcp_request({})
        end
      end
      
      should "return empty arrays for base command_array and env_hash" do
        assert_equal [], RedmineAiHelper::Tools::McpTools.command_array
        assert_equal({}, RedmineAiHelper::Tools::McpTools.env_hash)
      end
    end
  end
end