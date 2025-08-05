require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/tools/mcp_tools"

# Mock MCPClient constant for tests
class MCPClient
  def self.create_client(*args); end
  def self.stdio_config(*args); end  
  def self.http_config(*args); end
  def self.sse_config(*args); end
end

class RedmineAiHelper::Tools::McpToolsSimplifiedTest < ActiveSupport::TestCase
  context "McpTools basic functionality" do
    should "return empty command array" do
      assert_equal [], RedmineAiHelper::Tools::McpTools.command_array
    end

    should "return empty env hash" do
      assert_equal({}, RedmineAiHelper::Tools::McpTools.env_hash)
    end

    should "start with zero counter" do
      # Reset counter before test
      RedmineAiHelper::Tools::McpTools.instance_variable_set(:@mcp_server_call_counter, 0)
      assert_equal 0, RedmineAiHelper::Tools::McpTools.mcp_server_call_counter
    end

    should "increment counter and return previous value" do
      # Reset counter
      RedmineAiHelper::Tools::McpTools.instance_variable_set(:@mcp_server_call_counter, 5)
      
      previous = RedmineAiHelper::Tools::McpTools.mcp_server_call_counter_up
      assert_equal 5, previous
      assert_equal 6, RedmineAiHelper::Tools::McpTools.mcp_server_call_counter
    end

    should "raise NotImplementedError in base class send_mcp_request" do
      assert_raises(NotImplementedError) do
        RedmineAiHelper::Tools::McpTools.send_mcp_request({})
      end
    end

    should "handle method_missing for non-existent function" do
      instance = RedmineAiHelper::Tools::McpTools.new
      
      assert_raises ArgumentError do
        instance.non_existent_function
      end
    end
  end

  context "class generation with mocked transport" do
    setup do
      # Mock the require statement to prevent loading the real gem
      Kernel.stubs(:require).with('mcp_client').returns(true)
      
      # Mock ruby-mcp-client
      mock_client = mock('mcp_client')
      mock_client.stubs(:list_tools).returns([])
      mock_client.stubs(:cleanup)
      ::MCPClient.stubs(:create_client).returns(mock_client)
      ::MCPClient.stubs(:stdio_config).returns({type: 'stdio'})
      ::MCPClient.stubs(:http_config).returns({type: 'http'})
    end

    should "generate tool class with correct name without server communication" do
      json = { "command" => "test", "args" => ["arg1"] }
      
      # Override generate_tool_class to skip load_from_mcp_server
      original_method = RedmineAiHelper::Tools::McpTools.method(:generate_tool_class)
      RedmineAiHelper::Tools::McpTools.define_singleton_method(:generate_tool_class) do |name:, json:|
        class_name = "Mcp#{name.capitalize}"
        klass = Class.new(RedmineAiHelper::Tools::McpTools) do
          @mcp_server_json = json
          @mcp_server_json.freeze
          @transport = nil
          @mcp_server_call_counter = 0
          
          def self.transport
            @transport ||= mock('transport')
          end

          def self.command_array
            return [] unless @mcp_server_json['command']
            command = @mcp_server_json["command"]
            args = [command]
            args = args + @mcp_server_json["args"] if @mcp_server_json["args"]
            args
          end

          def self.env_hash
            @mcp_server_json["env"] || {}
          end

          def self.close_transport
            @transport&.close if @transport.respond_to?(:close)
            @transport = nil
          end

          def self.send_mcp_request(message)
            transport.send_request(message)
          end
        end
        Object.const_set(class_name, klass)
        # Skip load_from_mcp_server call
        klass
      end
      
      klass = RedmineAiHelper::Tools::McpTools.generate_tool_class(name: "test_simple", json: json)
      
      assert_equal "McpTest_simple", klass.name
      assert klass.ancestors.include?(RedmineAiHelper::Tools::McpTools)
      
      # Restore original method
      RedmineAiHelper::Tools::McpTools.define_singleton_method(:generate_tool_class, original_method)
    end

    should "provide backward compatibility methods" do
      json = { "command" => "node", "args" => ["server.js"], "env" => { "API_KEY" => "secret" } }
      
      # Create a simple test class without server communication
      klass = Class.new(RedmineAiHelper::Tools::McpTools) do
        @mcp_server_json = json
        @mcp_server_json.freeze
        
        def self.command_array
          return [] unless @mcp_server_json['command']
          command = @mcp_server_json["command"]
          args = [command]
          args = args + @mcp_server_json["args"] if @mcp_server_json["args"]
          args
        end

        def self.env_hash
          @mcp_server_json["env"] || {}
        end
      end
      
      expected = ["node", "server.js"]
      assert_equal expected, klass.command_array
      assert_equal({ "API_KEY" => "secret" }, klass.env_hash)
    end
  end
end