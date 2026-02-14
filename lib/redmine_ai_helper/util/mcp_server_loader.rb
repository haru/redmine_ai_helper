require "singleton"
require "json"

module RedmineAiHelper
  module Util
    # Loads MCP server definitions and generates dynamic agents.
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

        # Infer type if missing (backward compatibility):
        # - If command/args present => stdio
        # - If url present => http (default over sse since we cannot auto-detect sse reliably)
        config["type"] ||= infer_server_type(config)

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

      # Infer server type from available keys (internal helper)
      def infer_server_type(config)
        return "stdio" if config["command"] || config["args"]
        return "http" if config["url"]
        nil
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
        # Allow implicit type inference
        server_type = server_config["type"] || infer_server_type(server_config)
        case server_type
        when "stdio"
          create_stdio_client(server_name, server_config)
        when "http"
          create_http_client(server_name, server_config)
        when "sse"
          create_sse_client(server_name, server_config)
        else
          raise ArgumentError, "Unsupported MCP server type: #{server_config["type"] || "unknown"}"
        end
      end

      # Create STDIO MCP client
      def create_stdio_client(server_name, server_config)
        require "mcp_client"

        config = MCPClient.stdio_config(
          command: build_command_string(server_config),
          name: server_name,
          env: server_config["env"] || {},
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Create HTTP MCP client
      def create_http_client(server_name, server_config)
        require "mcp_client"

        config = MCPClient.http_config(
          base_url: server_config["url"],
          name: server_name,
          headers: server_config["headers"] || {},
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Create SSE MCP client
      def create_sse_client(server_name, server_config)
        require "mcp_client"

        config = MCPClient.sse_config(
          base_url: server_config["url"],
          name: server_name,
          headers: server_config["headers"] || {},
        )

        MCPClient.create_client(mcp_server_configs: [config], logger: nil)
      end

      # Build command string
      def build_command_string(server_config)
        if server_config["command"] && server_config["args"]
          "#{server_config["command"]} #{server_config["args"].join(" ")}"
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
            # Use the same identifier as registration (class underscored), e.g. AiHelperMcpSlack -> ai_helper_mcp_slack
            self.class.name.split("::").last.underscore
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

          define_method :available_tool_classes do
            # Cache tool classes
            return @cached_tool_classes if @cached_tool_classes

            mcp_tools_class = RedmineAiHelper::Tools::McpTools.generate_tool_class(
              mcp_server_name: server_name,
              mcp_client: mcp_client,
            )
            @cached_tool_classes = mcp_tools_class.tool_classes
          rescue => e
            ai_helper_logger.error "Error loading tools for MCP server '#{server_name}': #{e.message}"
            []
          end

          define_method :backstory do
            # Cache backstory to avoid regeneration for the same MCP agent class
            return @cached_backstory if @cached_backstory

            # Generate backstory strictly from prompt template (no fallback)
            prompt = load_prompt("mcp_agent/backstory")
            base_backstory = prompt.format(server_name: server_name)

            tools_info = ""
            begin
              tools_list = available_tools
              if tools_list.is_a?(Array) && !tools_list.empty?
                tools_info += "\n\nAvailable tools (#{server_name}):\n"
                tools_list.each do |tool|
                  if tool.is_a?(Hash) && tool.dig(:function, :description)
                    description = tool.dig(:function, :description)
                    tools_info += "- #{description}\n"
                  end
                end
              else
                tools_info += "\n\nNo tools available at the moment for #{server_name}."
              end
            rescue => e
              # Log tool info retrieval errors but do not mask prompt issues
              ai_helper_logger.error "Error retrieving tools information for '#{server_name}': #{e.message}"
              raise
            end

            @cached_backstory = base_backstory + tools_info
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
