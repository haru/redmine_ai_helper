require 'singleton'
require 'json'

module RedmineAiHelper
  module Util
    class McpServerLoader
      include Singleton
      include RedmineAiHelper::Logger

      # Executed once when Redmine starts up
      def self.load_all
        instance.generate_mcp_agent_classes
      end

      # Dynamically generate MCP agent subclasses from MCP server configuration
      def generate_mcp_agent_classes
        return if @agents_generated

        config_data = load_config
        mcp_servers = config_data["mcpServers"]
        return unless mcp_servers

        mcp_servers.each do |server_name, server_config|
          begin
            # Validate server configuration
            unless valid_server_config?(server_config)
              ai_helper_logger.warn "Invalid configuration for MCP server '#{server_name}': #{server_config}"
              next
            end

            # Generate class name
            class_name = "AiHelperMcp#{server_name.camelize}"

            # Avoid duplicate class definitions
            if Object.const_defined?(class_name)
              ai_helper_logger.debug "MCP agent class '#{class_name}' already exists, skipping"
              next
            end

            # Create MCP client
            mcp_client = create_mcp_client(server_name, server_config)

            # Create dynamic subclass
            create_mcp_agent_subclass(class_name, server_name, mcp_client)

            ai_helper_logger.info "Successfully created MCP agent: #{class_name} for server '#{server_name}'"

          rescue => e
            ai_helper_logger.error "Error creating MCP agent for '#{server_name}': #{e.message}"
            ai_helper_logger.error e.backtrace.join("\n")
          end
        end

        @agents_generated = true
      end

      private

      # Load configuration file
      def load_config
        config_file_path = Rails.root.join("config", "ai_helper", "config.json")
        
        unless File.exist?(config_file_path)
          ai_helper_logger.warn "MCP config file not found: #{config_file_path}"
          return {}
        end

        JSON.parse(File.read(config_file_path))
      rescue JSON::ParserError => e
        ai_helper_logger.error "Invalid JSON in config file: #{e.message}"
        {}
      rescue => e
        ai_helper_logger.error "Error reading config file: #{e.message}"
        {}
      end

      # Validate server configuration
      def valid_server_config?(config)
        return false unless config.is_a?(Hash)
        return false unless config["type"]

        case config["type"]
        when "stdio"
          !!(config["command"] || config["args"])
        when "http", "sse"
          !!(config["url"] && valid_url?(config["url"]))
        else
          false
        end
      end

      # Validate URL format
      def valid_url?(url)
        uri = URI.parse(url)
        %w[http https].include?(uri.scheme)
      rescue URI::InvalidURIError
        false
      end

      # Create MCP client
      def create_mcp_client(server_name, server_config)
        case server_config["type"]
        when "stdio"
          create_stdio_client(server_name, server_config)
        when "http"
          create_http_client(server_name, server_config)
        when "sse"
          create_sse_client(server_name, server_config)
        else
          raise ArgumentError, "Unsupported MCP server type: #{server_config['type']}"
        end
      end

      # Create STDIO MCP client
      def create_stdio_client(server_name, server_config)
        require 'mcp_client'

        config = MCPClient.stdio_config(
          command: build_command_string(server_config),
          name: server_name,
          env: server_config["env"] || {}
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Create HTTP MCP client
      def create_http_client(server_name, server_config)
        require 'mcp_client'

        config = MCPClient.http_config(
          base_url: server_config["url"],
          name: server_name,
          headers: server_config["headers"] || {}
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Create SSE MCP client
      def create_sse_client(server_name, server_config)
        require 'mcp_client'

        config = MCPClient.sse_config(
          base_url: server_config["url"],
          name: server_name,
          headers: server_config["headers"] || {}
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Build command string
      def build_command_string(server_config)
        if server_config["command"] && server_config["args"]
          "#{server_config['command']} #{server_config['args'].join(' ')}"
        elsif server_config["command"]
          server_config["command"]
        elsif server_config["args"]
          server_config["args"].join(" ")
        else
          raise ArgumentError, "Either 'command' or 'args' must be specified for stdio MCP server"
        end
      end

      # Dynamically create MCP agent subclass
      def create_mcp_agent_subclass(class_name, server_name, mcp_client)
        sub_agent_class = Class.new(RedmineAiHelper::BaseAgent) do
          @server_name = server_name
          @mcp_client = mcp_client

          class << self
            attr_reader :server_name, :mcp_client
          end

          define_method :role do
            "mcp_#{server_name}"
          end

          define_method :name do
            class_name
          end

          define_method :to_s do
            class_name
          end

          define_method :enabled? do
            true
          end

          define_method :available_tool_providers do
            # Hold tool providers as class variable
            return @tool_providers if @tool_providers

            @tool_providers = [
              RedmineAiHelper::Tools::McpTools.generate_tool_class(
                mcp_server_name: server_name,
                mcp_client: mcp_client
              )
            ]
            @tool_providers
          rescue => e
            ai_helper_logger.error "Error loading tools for MCP server '#{server_name}': #{e.message}"
            []
          end

          define_method :backstory do
            # Get backstory from parent class (McpAgent)
            base_backstory = begin
              prompt = load_prompt("mcp_agent/backstory")
              prompt.format(server_name: server_name)
            rescue => e
              # Fallback message
              "I am an AI agent specialized in using the #{server_name} MCP server. I can help you with tasks that require interaction with #{server_name} services."
            end

            # Get information about available tools
            tools_info = ""
            begin
              # Get tool schemas using available_tools method
              tools_list = available_tools
              if tools_list.is_a?(Array) && !tools_list.empty?
                tools_info += "\n\nAvailable tools:\n"
                tools_list.each do |tool_schemas|
                  if tool_schemas.is_a?(Array)
                    tool_schemas.each do |tool|
                      if tool.is_a?(Hash) && tool.dig(:function, :name) && tool.dig(:function, :description)
                        function_name = tool.dig(:function, :name)
                        description = tool.dig(:function, :description)
                        tools_info += "- **#{function_name}**: #{description}\n"
                      end
                    end
                  end
                end
              else
                tools_info += "\n\nNo tools available at the moment."
              end
            rescue => e
              tools_info += "\n\nError retrieving tools information: #{e.message}"
            end

            # Add tool information to parent class backstory
            base_backstory + tools_info
          end

          # Set class name with singleton method
          define_singleton_method :name do
            class_name
          end

          define_singleton_method :to_s do
            class_name
          end
        end

        # Set as constant
        Object.const_set(class_name, sub_agent_class)

        # Register with BaseAgent
        RedmineAiHelper::BaseAgent.register_pending_dynamic_class(sub_agent_class, class_name)
      end
    end
  end
end