require "singleton"
require "json"
require "ruby_llm/mcp"

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
        config_file_path = Rails.root.join("config/ai_helper/config.json")

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

      # Create STDIO MCP client using ruby_llm-mcp
      def create_stdio_client(server_name, server_config)
        RubyLLM::MCP.client(
          name: server_name,
          transport_type: :stdio,
          config: {
            command: build_command_string(server_config),
            env: server_config["env"] || {}
          }
        )
      end

      # Create HTTP MCP client using ruby_llm-mcp (streamable transport)
      def create_http_client(server_name, server_config)
        RubyLLM::MCP.client(
          name: server_name,
          transport_type: :streamable,
          config: {
            url: server_config["url"],
            headers: server_config["headers"] || {}
          }
        )
      end

      # Create SSE MCP client using ruby_llm-mcp
      def create_sse_client(server_name, server_config)
        RubyLLM::MCP.client(
          name: server_name,
          transport_type: :sse,
          config: {
            url: server_config["url"],
            headers: server_config["headers"] || {}
          }
        )
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
        loader = self
        sub_agent_class = Class.new(RedmineAiHelper::BaseAgent) do
          @server_name = server_name
          @mcp_client = mcp_client

          class << self
            attr_reader :server_name, :mcp_client
          end

          define_method(:role) { self.class.name.split("::").last.underscore }
          define_method(:name) { class_name }
          define_method(:to_s) { class_name }
          # External MCP tools have no write/read classification, so we disable
          # the entire agent rather than filtering individual tools (see ADR-005).
          define_method(:enabled?) { !AiHelperSetting.read_only_mode? }

          define_method :available_tool_classes do
            return @cached_tool_classes if @cached_tool_classes
            @cached_tool_classes = RedmineAiHelper::Tools::McpTools.generate_tool_classes(
              mcp_server_name: server_name,
              mcp_client: mcp_client
            )
          rescue => e
            ai_helper_logger.error "Error loading tools for MCP server '#{server_name}': #{e.message}"
            []
          end

          # Override available_tools to handle MCP tool instances
          # (MCP tools are RubyLLM::Tool instances, not classes)
          define_method :available_tools do
            available_tool_classes.map do |tool|
              { function: { name: tool.name, description: tool.description } }
            end
          end

          define_method :backstory do
            return @cached_backstory if @cached_backstory

            base = load_prompt("mcp_agent/backstory").format(server_name: server_name)
            begin
              tools_info = loader.format_mcp_tools_info(server_name, available_tools)
            rescue => e
              ai_helper_logger.error "Error retrieving tools information for '#{server_name}': #{e.message}"
              raise
            end
            @cached_backstory = base + tools_info
          end

          define_singleton_method(:name) { class_name }
          define_singleton_method(:to_s) { class_name }
        end

        Object.const_set(class_name, sub_agent_class)
        RedmineAiHelper::BaseAgent.register_pending_dynamic_class(sub_agent_class, class_name)
      end

      public

      # Format the tools info section of an MCP agent backstory.
      def format_mcp_tools_info(server_name, tools_list)
        return "\n\nNo tools available at the moment for #{server_name}." unless tools_list.is_a?(Array) && !tools_list.empty?

        info = "\n\nAvailable tools (#{server_name}):\n"
        tools_list.each do |tool|
          description = tool.is_a?(Hash) ? tool.dig(:function, :description) : nil
          info += "- #{description}\n" if description
        end
        info
      end
    end
  end
end
