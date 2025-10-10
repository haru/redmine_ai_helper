module RedmineAiHelper
  # Tools namespace for agent capabilities
  module Tools
    # MCP (Model Context Protocol) tools for dynamic server integration
    class McpTools < RedmineAiHelper::BaseTools
      using RedmineAiHelper::Util::LangchainPatch
      include RedmineAiHelper::Logger

      class << self
        # Dynamically generate tool class for MCP Server
        # @param mcp_server_name [String] MCP server name
        # @param mcp_client [Object] MCP client instance
        # @return [Class] Generated tool class
        def generate_tool_class(mcp_server_name:, mcp_client:)
          # Short class naming pattern: AiHleprMcp1, AiHleprMcp2, ...
          @@server_tool_class_map ||= {}
          @@short_class_counter ||= 0

          if @@server_tool_class_map[mcp_server_name]
            const_name = @@server_tool_class_map[mcp_server_name]
            return Object.const_get(const_name) if Object.const_defined?(const_name)
          end

          begin
            @@short_class_counter += 1
            const_name = "AiHleprMcp#{@@short_class_counter}"
          end while Object.const_defined?(const_name)

          @@server_tool_class_map[mcp_server_name] = const_name

          class_name = const_name

          # Dynamically generate tool class
          tool_class = Class.new(RedmineAiHelper::Tools::McpTools) do
            @mcp_server_name = mcp_server_name
            @mcp_client = mcp_client

            class << self
              attr_reader :mcp_server_name, :mcp_client
            end

            # Get tool list from MCP server and generate ToolDefinition
            define_singleton_method :load_tools_from_mcp_server do
              begin
                # Cache tools list per MCP server to avoid multiple requests
                @cached_tools ||= @mcp_client.list_tools
                tools = @cached_tools
                load_tools_from_list(tools)
                RedmineAiHelper::CustomLogger.instance.info "Loaded #{tools.size} tools from MCP server '#{@mcp_server_name}'"
              rescue => e
                RedmineAiHelper::CustomLogger.instance.error "Error loading tools from MCP server '#{@mcp_server_name}': #{e.message}"
                RedmineAiHelper::CustomLogger.instance.error e.backtrace.join("\n")
              end
            end

            # Helper method to return default schema (defined at class level)
            define_singleton_method :default_schema do
              {
                "type" => "object",
                "properties" => {
                  "dummy_property" => {
                    "type" => "string",
                    "description" => "dummy property for tools without parameters",
                  },
                },
                "required" => [],
              }
            end

            # Helper method to normalize schema (defined at class level)
            define_singleton_method :normalize_input_schema do |schema|
              return default_schema if schema.nil?

              # Use default schema if properties is nil or empty
              if schema.dig("properties").nil? ||
                 (schema.dig("properties").is_a?(Hash) && schema.dig("properties").empty?)
                return default_schema
              end

              # Use default schema if properties is an empty object
              properties = schema.dig("properties")
              if properties.is_a?(Hash) && properties.keys.empty?
                return default_schema
              end

              # Check if each property has appropriate structure
              if properties.is_a?(Hash)
                properties.each do |key, value|
                  unless value.is_a?(Hash) && value.key?("type")
                    # Use default schema if invalid property found
                    return default_schema
                  end
                end
              end

              schema
            end

            # Generate ToolDefinition from tool list
            define_singleton_method :load_tools_from_list do |tools|
              # Extend langchain_patch to make build_properties_from_json method available
              extend RedmineAiHelper::Util::LangchainPatch

              tools.each do |tool|
                begin
                  # Normalize schema in advance
                  input_schema = normalize_input_schema(tool.schema)

                  define_function tool.name, description: tool.description do
                    # Use normalized schema
                    build_properties_from_json(input_schema)
                  end
                rescue => e
                  RedmineAiHelper::CustomLogger.instance.error "Error loading tool '#{tool.name}' from MCP server '#{@mcp_server_name}': #{e.message}"
                  # Continue processing even if tool loading fails
                  next
                end
              end
            end

            # Called when tool is executed
            define_method :method_missing do |method_name, *args|
              # Search for target function from function schema
              schema = self.class.function_schemas.to_openai_format
              # Perform search compatible with langchainrb naming conventions
              function = schema.find do |f|
                function_name = f.dig(:function, :name)
                # Exact match, pattern ending with __, or direct tool name
                function_name == method_name.to_s ||
                function_name&.end_with?("__#{method_name}") ||
                function_name&.split("__").last == method_name.to_s
              end

              unless function
                available_functions = schema.map { |f| f.dig(:function, :name) }
                raise ArgumentError, "Function not found: #{method_name}. Available: #{available_functions.join(", ")}"
              end

              begin
                # Execute tool with MCP client
                arguments = args[0] || {}
                # Remove dummy_property if it exists
                arguments.delete("dummy_property") if arguments.is_a?(Hash)

                result = self.class.mcp_client.call_tool(method_name.to_s, arguments)

                # Return result as string
                case result
                when String
                  result
                when Hash, Array
                  result.to_json
                else
                  result.to_s
                end
              rescue => e
                ai_helper_logger.error "Error calling MCP tool '#{method_name}' on server '#{self.class.mcp_server_name}': #{e.message}"
                "Error: #{e.message}"
              end
            end

            # Set class name
            define_singleton_method :name do
              class_name
            end

            define_singleton_method :to_s do
              class_name
            end
          end

          # Set as constant
          Object.const_set(class_name, tool_class)

          # Load tools from MCP server
          tool_class.load_tools_from_mcp_server

          tool_class
        end
      end
    end
  end
end
