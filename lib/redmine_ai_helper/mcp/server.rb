# frozen_string_literal: true

require "mcp"
require_relative "tool_adapter"
require "redmine_ai_helper/logger"

module RedmineAiHelper
  # Namespace for MCP (Model Context Protocol) server components.
  module Mcp
    # Builds an MCP::Server instance populated with all registered BaseTools
    # subclasses, filtered by the authenticated user's permissions and current settings.
    #
    # @example
    #   server = Server.build
    #   transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    class Server
      include RedmineAiHelper::Logger
      class << self
        # Builds and returns a configured MCP::Server with tools filtered for the given user.
        #
        # @param user [User] authenticated user (defaults to User.current)
        # @return [MCP::Server] server instance with permitted tools registered
        def build(user: User.current)
          mcp_tools = collect_tools(user: user)

          MCP::Server.new(
            name: "redmine-ai-helper",
            version: plugin_version,
            instructions: "Redmine AI Helper MCP Server. All tools respect Redmine permissions.",
            tools: mcp_tools
          )
        end

        # Returns true if the named MCP tool is permitted for the given user.
        # Used by the controller to reject tools/call before routing to the MCP transport.
        #
        # @param tool_name [String] MCP tool name (e.g. "ask_with_filter")
        # @param user [User] authenticated user
        # @return [Boolean]
        def tool_call_permitted?(tool_name, user:)
          load_all_tool_files
          RedmineAiHelper::BaseTools.subclasses.each do |base_tools_class|
            next if base_tools_class.name.nil?
            base_tools_class.tool_classes.each do |ruby_tool_class|
              mcp_name = ToolAdapter.send(:extract_tool_name, ruby_tool_class.new)
              next unless mcp_name == tool_name
              if AiHelperSetting.read_only_mode? && ruby_tool_class.write_tool?
                ai_helper_logger.debug("MCP tools/call #{tool_name} denied: read-only mode is enabled")
                return false
              end
              return mcp_tool_allowed?(base_tools_class, user: user)
            end
          end
          true
        end

        private

        # Eagerly loads all tool files so BaseTools.subclasses is complete.
        # Tools are autoloaded lazily in development/test; calling this ensures
        # all subclasses are registered before we enumerate them.
        def load_all_tool_files
          tools_dir = File.expand_path("../../tools", __FILE__)
          Dir[File.join(tools_dir, "*.rb")].sort.each { |f| require f }
        end

        # Collects and adapts all BaseTools subclasses into MCP::Tool subclasses,
        # filtering out classes whose permission requirements are not met for the user.
        #
        # @param user [User] authenticated user
        # @return [Array<Class>] array of MCP::Tool subclasses
        def collect_tools(user:)
          load_all_tool_files
          read_only = AiHelperSetting.read_only_mode?
          tools = []
          RedmineAiHelper::BaseTools.subclasses.each do |base_tools_class|
            next if base_tools_class.name.nil?
            next unless mcp_tool_allowed?(base_tools_class, user: user)

            base_tools_class.tool_classes.each do |ruby_tool_class|
              if read_only && ruby_tool_class.write_tool?
                ai_helper_logger.debug("MCP tool #{ruby_tool_class.name} excluded: read-only mode is enabled")
                next
              end
              tools << ToolAdapter.adapt(ruby_tool_class, source_tools_class: base_tools_class)
            end
          end
          tools
        end

        # Returns true if the tool class is permitted for the given user.
        #
        # @param tool_class [Class] a BaseTools subclass
        # @param user [User] authenticated user
        # @return [Boolean]
        def mcp_tool_allowed?(tool_class, user:)
          reqs = tool_class.permission_requirements
          return true if reqs.empty?
          if reqs[:vector_db_enabled]
            unless AiHelperSetting.vector_search_enabled?
              ai_helper_logger.debug("MCP tool #{tool_class.name} excluded: vector_db_enabled required but disabled")
              return false
            end
          end
          if reqs[:admin]
            unless user.admin?
              ai_helper_logger.debug("MCP tool #{tool_class.name} excluded: admin required but user is non-admin")
              return false
            end
          end
          true
        end

        # Returns the plugin version string.
        #
        # @return [String] plugin version
        def plugin_version
          Redmine::Plugin.find(:redmine_ai_helper).version
        end
      end
    end

    # @deprecated Use {Server} directly.
    McpServerBuilder = Server
  end
end
