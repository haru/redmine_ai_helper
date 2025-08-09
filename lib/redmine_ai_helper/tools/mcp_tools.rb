# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/langchain_patch"

module RedmineAiHelper
  module Tools
    # McpTools is a specialized tool class for handling tasks using the Model Context Protocol (MCP).
    # It allows for the execution of commands and interaction with external tools or services.
    # This class is designed to be used in conjunction with the MCP server, which provides a JSON-RPC interface for tool execution.
    # The class dynamically generates tool classes based on the MCP server's JSON definition.
    # The generated tool classes can be used to define functions and execute commands with specific input schemas.
    # Updated to use the new transport abstraction layer to support both STDIO and HTTP+SSE transports.
    class McpTools < RedmineAiHelper::BaseTools
      using RedmineAiHelper::Util::LangchainPatch

      class << self

        # Generate tool classes based on the definition JSON from the MCP server
        # The JSON format supports both STDIO and HTTP transports using ruby-mcp-client:
        # STDIO format (detected by presence of 'command' or 'args'):
        # {
        #     "command": "npx",
        #     "args": ["-y", "@modelcontextprotocol/server-slack"],
        #     "env": {"SLACK_BOT_TOKEN": "xoxb-your-bot-token"}
        # }
        # HTTP format (detected by presence of 'url'):
        # {
        #     "url": "http://localhost:3000",
        #     "headers": {"Authorization": "Bearer token"},
        #     "timeout": 30
        # }
        # @param name [String] The name of the tool class to be generated.
        # @param json [Hash] The JSON definition of the tool class.
        # @return [Class] The generated tool class.
        def generate_tool_class(name:, json:)
          class_name = "Mcp#{name.capitalize}"
          
          # Check if class already exists to avoid redefinition warnings
          if Object.const_defined?(class_name)
            return Object.const_get(class_name)
          end
          
          Object.const_set(class_name,
                           Class.new(RedmineAiHelper::Tools::McpTools) do
            @mcp_server_json = json
            @mcp_server_json.freeze
            @mcp_client = nil
            @mcp_server_call_counter = 0
            
            def self.mcp_client
              return @mcp_client if @mcp_client
              
              begin
                require 'mcp_client'
                
                # Use server_definition_file to load config directly
                config_path = '/usr/local/redmine/config/ai_helper/config.json'
                
                @mcp_client = ::MCPClient.create_client(
                  server_definition_file: config_path,
                  logger: nil
                )
                
                @mcp_client
              rescue => e
                Rails.logger.error "Failed to create MCP client: #{e.message}"
                raise
              end
            end

            # Backward compatibility methods (existing code may depend on these)
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

            # Close the MCP client
            def self.close_transport
              @mcp_client&.cleanup
              @mcp_client = nil
            end

            # Send MCP request using ruby-mcp-client
            def self.send_mcp_request(message)
              method_name = message['method']
              params = message['params'] || {}
              
              case method_name
              when 'tools/list'
                tools = mcp_client.list_tools
                {
                  'jsonrpc' => '2.0',
                  'id' => message['id'],
                  'result' => {
                    'tools' => tools.map do |tool|
                      {
                        'name' => tool.name,
                        'description' => tool.description,
                        'inputSchema' => tool.schema || {}
                      }
                    end
                  }
                }
              when 'tools/call'
                tool_name = params['name']
                arguments = params['arguments'] || {}
                
                result = mcp_client.call_tool(tool_name, arguments)
                
                {
                  'jsonrpc' => '2.0',
                  'id' => message['id'],
                  'result' => {
                    'content' => [
                      {
                        'type' => 'text',
                        'text' => result.to_s
                      }
                    ]
                  }
                }
              else
                raise NotImplementedError, "Unsupported method: #{method_name}"
              end
            rescue => e
              {
                'jsonrpc' => '2.0',
                'id' => message['id'],
                'error' => {
                  'code' => -1,
                  'message' => e.message
                }
              }
            end
          end)
          klass = Object.const_get(class_name)
          klass.load_from_mcp_server
          klass
        end

        # Returns the number of times the MCP server has been executed.
        # Used to ensure the uniqueness of the message ID passed to the MCP server.
        def mcp_server_call_counter
          @mcp_server_call_counter ||= 0
        end

        # Increments the MCP server call counter and returns the previous value.
        def mcp_server_call_counter_up
          before = mcp_server_call_counter
          @mcp_server_call_counter = before + 1
          before
        end

        # Returns the command line for the MCP server.
        # Automatically overridden in the subclass to provide the command line.
        # @return [Array] An array representing the command line.
        def command_array
          []
        end

        # Returns the environment variables for the MCP server.
        # Automatically overridden in the subclass to provide the environment variables.
        # @return [Hash] A hash representing the environment variables.
        def env_hash
          {}
        end

        # Executes the MCP command with the provided input JSON.
        # @deprecated Use send_mcp_request instead which supports multiple transports
        # @param input_json [String] The input JSON to be passed to the MCP server.
        # @return [String] The output from the MCP server.
        def execut_mcp_command(input_json:)
          # For backward compatibility, use the new transport system
          message = JSON.parse(input_json)
          response = send_mcp_request(message)
          response.to_json
        end

        # Sends a request to the MCP server using ruby-mcp-client.
        # @param message [Hash] The JSON-RPC message to send.
        # @return [Hash] The response from the MCP server.
        def send_mcp_request(message)
          # This method should be overridden in generated subclasses to use their mcp_client
          raise NotImplementedError, "send_mcp_request must be implemented in generated subclass"
        end

        # Loads the tools from the MCP server.
        # This method sends a request to the MCP server to retrieve the list of tools.
        # The response is then parsed and the tools are loaded into the class.
        # @return [Array] An array of loaded tools.
        def load_from_mcp_server
          request_message = {
            "method" => "tools/list",
            "params" => {},
            "jsonrpc" => "2.0",
            "id" => mcp_server_call_counter_up,
          }
          @mcp_server_call_counter += 1
          
          response = send_mcp_request(request_message)

          # Parse the response to retrieve the list of tools
          tools = response.dig("result", "tools") rescue nil

          load_json(json: tools)
        end

        # Loads the JSON definition of the tools and defines functions based on it.
        # This method iterates through the provided JSON and dynamically defines functions for each tool.
        #
        def load_json(json:)
          tools = [json]
          tools = json if json.is_a?(Array)
          tools.each do |tool|
            define_function tool["name"], description: tool["description"] do
              input_schema = tool["inputSchema"]
              if input_schema["properties"].empty?
                input_schema["properties"] = { "dummy_property" => { "type" => "string", "description" => "dummy property" } }
              end
              build_properties_from_json(input_schema)
            end
          end
        end
      end

      # Method executed when a tool from the MCP server is invoked
      # Requests the MCP server to execute the tool specified by name
      # @param name [String] The name of the tool to be executed.
      # @param args [Array] The arguments to be passed to the tool.
      # @return [String] The output from the MCP server.
      # @raise [ArgumentError] If the tool is not found.
      def method_missing(name, *args)
        schema = self.class.function_schemas.to_openai_format
        function = schema.find { |f| f.dig(:function, :name).end_with?("__#{name}") }

        raise ArgumentError, "Function not found: #{name}" unless function

        request_message = {
          "method" => "tools/call",
          "params" => {
            "name" => name.to_s,
            "arguments" => args[0],
          },
          "jsonrpc" => "2.0",
          "id" => self.class.mcp_server_call_counter_up,
        }

        response = self.class.send_mcp_request(request_message)

        # Return response as string for backward compatibility
        response.to_json
      end
    end
  end
end
