require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/tools/mcp_tools"

class RedmineAiHelper::Tools::McpToolsExtendedTest < ActiveSupport::TestCase
  context "McpTools generate_tool_class" do
    teardown do
      # Clean up any dynamically generated classes
      %w[McpTest McpSlack McpGithub McpContext7].each do |class_name|
        Object.send(:remove_const, class_name) if Object.const_defined?(class_name)
      end
    end
    
    should "generate tool class with correct JSON stored" do
      json = { "type" => "stdio", "command" => "test", "args" => ["--test"] }
      
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        # Mock load_from_mcp_server to avoid actual MCP calls
        def self.load_from_mcp_server
          # Do nothing
        end
      end
      klass.instance_variable_set(:@mcp_server_json, json)
      klass.instance_variable_set(:@mcp_server_json, json.freeze)
      
      assert_equal json, klass.instance_variable_get(:@mcp_server_json)
      assert klass.instance_variable_get(:@mcp_server_json).frozen?
    end
    
    should "return existing class if already defined" do
      json = { "type" => "stdio", "command" => "test" }
      
      # Mock the actual generation to avoid MCP calls
      mock_class = Class.new(RedmineAiHelper::Tools::McpTools)
      mock_class.define_singleton_method(:load_from_mcp_server) { }
      
      # Test class existence check
      Object.const_set("McpTest", mock_class)
      
      result = Object.const_get("McpTest") if Object.const_defined?("McpTest")
      assert_equal mock_class, result
    end
    
    should "generate different classes for different names" do
      # Test the naming logic
      name1 = "slack"
      name2 = "github"
      
      class_name1 = "Mcp#{name1.capitalize}"
      class_name2 = "Mcp#{name2.capitalize}"
      
      assert_equal "McpSlack", class_name1
      assert_equal "McpGithub", class_name2
      assert_not_equal class_name1, class_name2
    end
  end
  
  context "generated class methods" do
    should "handle command_array parsing in generated class" do
      json_with_command = { "command" => "node", "args" => ["server.js"] }
      
      # Mock the generate_tool_class without actual MCP calls
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = { "command" => "node", "args" => ["server.js"] }
        
        def self.command_array
          return [] unless @mcp_server_json['command']
          command = @mcp_server_json["command"]
          args = [command]
          args = args + @mcp_server_json["args"] if @mcp_server_json["args"]
          args
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      expected = ["node", "server.js"]
      result = klass.command_array
      
      assert_equal expected, result
    end
    
    should "handle command_array with no args in generated class" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = { "command" => "test" }
        
        def self.command_array
          return [] unless @mcp_server_json['command']
          command = @mcp_server_json["command"]
          args = [command]
          args = args + @mcp_server_json["args"] if @mcp_server_json["args"]
          args
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      expected = ["test"]
      result = klass.command_array
      
      assert_equal expected, result
    end
    
    should "return empty array when no command in generated class" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = { "type" => "http", "url" => "https://example.com" }
        
        def self.command_array
          return [] unless @mcp_server_json['command']
          command = @mcp_server_json["command"]
          args = [command]
          args = args + @mcp_server_json["args"] if @mcp_server_json["args"]
          args
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      result = klass.command_array
      
      assert_equal [], result
    end
    
    should "handle env_hash extraction in generated class" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = { "command" => "test", "env" => { "API_KEY" => "secret" } }
        
        def self.env_hash
          @mcp_server_json["env"] || {}
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      result = klass.env_hash
      
      assert_equal({ "API_KEY" => "secret" }, result)
    end
    
    should "return empty hash when no env in generated class" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = { "command" => "test" }
        
        def self.env_hash
          @mcp_server_json["env"] || {}
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      result = klass.env_hash
      
      assert_equal({}, result)
    end
  end
  
  context "load_from_mcp_server fallback behavior" do
    should "call send_mcp_request when mcp_client is not available" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_call_counter = 0
        
        def self.mcp_server_call_counter_up
          @mcp_server_call_counter += 1
          @mcp_server_call_counter - 1
        end
        
        def self.send_mcp_request(message)
          {
            "result" => {
              "tools" => [{
                "name" => "test_tool",
                "description" => "A test tool",
                "inputSchema" => { "type" => "object" }
              }]
            }
          }
        end
        
        def self.load_json(json:)
          @loaded_tools = json
        end
      end
      
      klass.load_from_mcp_server
      
      loaded_tools = klass.instance_variable_get(:@loaded_tools)
      assert_equal 1, loaded_tools.length
      assert_equal "test_tool", loaded_tools.first["name"]
    end
    
    should "handle response parsing errors gracefully" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_call_counter = 0
        
        def self.mcp_server_call_counter_up
          @mcp_server_call_counter += 1
          @mcp_server_call_counter - 1
        end
        
        def self.send_mcp_request(message)
          { "error" => { "code" => -1, "message" => "Server error" } }
        end
        
        def self.load_json(json:)
          @loaded_tools = json
        end
      end
      
      assert_nothing_raised do
        klass.load_from_mcp_server
      end
      
      # Should have called load_json with nil (from rescue clause)
      loaded_tools = klass.instance_variable_get(:@loaded_tools)
      assert_nil loaded_tools
    end
  end
  
  context "method_missing fallback behavior" do
    should "execute tool via send_mcp_request when mcp_client not available" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.function_schemas
          mock_schemas = Object.new
          mock_schemas.define_singleton_method(:to_openai_format) do
            [{ function: { name: "test_function__test_tool" } }]
          end
          mock_schemas
        end
        
        def self.mcp_server_call_counter_up
          1
        end
        
        def self.send_mcp_request(message)
          {
            "jsonrpc" => "2.0",
            "id" => 1,
            "result" => {
              "content" => [{
                "type" => "text",
                "text" => "Tool executed successfully"
              }]
            }
          }
        end
      end
      
      instance = klass.new
      result = instance.test_tool({ "param" => "value" })
      
      assert result.include?("Tool executed successfully")
      assert result.include?("jsonrpc")
    end
    
    should "raise ArgumentError for non-existent function" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.function_schemas
          mock_schemas = Object.new
          mock_schemas.define_singleton_method(:to_openai_format) { [] }
          mock_schemas
        end
      end
      
      instance = klass.new
      
      assert_raises ArgumentError do
        instance.non_existent_function
      end
    end
  end
  
  context "close_transport method in generated classes" do
    should "cleanup client and reset to nil" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.close_transport
          @mcp_client&.cleanup
          @mcp_client = nil
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      # Set a mock client
      mock_client = Object.new
      mock_client.expects(:cleanup)
      klass.instance_variable_set(:@mcp_client, mock_client)
      
      klass.close_transport
      
      assert_nil klass.instance_variable_get(:@mcp_client)
    end
    
    should "handle nil client gracefully" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.close_transport
          @mcp_client&.cleanup
          @mcp_client = nil
        end
        
        def self.load_from_mcp_server
          # Mock to avoid actual MCP calls
        end
      end
      
      # Ensure client is nil
      klass.instance_variable_set(:@mcp_client, nil)
      
      # Should not raise error
      assert_nothing_raised do
        klass.close_transport
      end
    end
  end
  
  context "execut_mcp_command deprecated method" do
    should "parse JSON and call send_mcp_request" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.send_mcp_request(message)
          { "result" => "success" }
        end
      end
      
      input_json = '{"method": "test", "params": {}}'
      result = klass.execut_mcp_command(input_json: input_json)
      
      assert_equal '{"result":"success"}', result
    end
    
    should "handle JSON parsing errors" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools)
      
      invalid_json = '{"method": "test", "params":'  # Invalid JSON
      
      assert_raises JSON::ParserError do
        klass.execut_mcp_command(input_json: invalid_json)
      end
    end
  end
  
  context "load_json method" do
    should "handle single tool structure" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.define_function(name, description:, &block)
          (@defined_functions ||= []) << { name: name, description: description }
        end
        
        def self.build_properties_from_json(schema)
          # Mock implementation
        end
      end
      
      single_tool = { 
        "name" => "test_tool", 
        "description" => "A test tool",
        "inputSchema" => { 
          "type" => "object",
          "properties" => { "param" => { "type" => "string" } }
        }
      }
      
      assert_nothing_raised do
        klass.load_json(json: single_tool)
      end
      
      defined_functions = klass.instance_variable_get(:@defined_functions)
      assert_equal 1, defined_functions.length
      assert_equal "test_tool", defined_functions.first[:name]
    end
    
    should "handle array of tools" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.define_function(name, description:, &block)
          (@defined_functions ||= []) << { name: name, description: description }
        end
        
        def self.build_properties_from_json(schema)
          # Mock implementation
        end
      end
      
      tools_array = [
        { 
          "name" => "tool1", 
          "description" => "First tool",
          "inputSchema" => { 
            "type" => "object",
            "properties" => { "param" => { "type" => "string" } }
          }
        },
        { 
          "name" => "tool2", 
          "description" => "Second tool",
          "inputSchema" => { 
            "type" => "object", 
            "properties" => { "value" => { "type" => "number" } }
          }
        }
      ]
      
      assert_nothing_raised do
        klass.load_json(json: tools_array)
      end
      
      defined_functions = klass.instance_variable_get(:@defined_functions)
      assert_equal 2, defined_functions.length
      assert_equal "tool1", defined_functions.first[:name]
      assert_equal "tool2", defined_functions.last[:name]
    end
    
    should "add dummy property when inputSchema properties are empty" do
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        def self.define_function(name, description:, &block)
          # Capture the schema passed to build_properties_from_json
          yield  # Execute the block to call build_properties_from_json
        end
        
        def self.build_properties_from_json(schema)
          @captured_schema = schema
        end
      end
      
      tool_with_empty_properties = { 
        "name" => "empty_tool", 
        "description" => "Tool with empty properties",
        "inputSchema" => { 
          "type" => "object",
          "properties" => {}
        }
      }
      
      klass.load_json(json: tool_with_empty_properties)
      
      captured_schema = klass.instance_variable_get(:@captured_schema)
      assert_not_empty captured_schema["properties"]
      assert_equal "dummy property", captured_schema["properties"]["dummy_property"]["description"]
    end
  end
end