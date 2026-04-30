# frozen_string_literal: true

require "mcp"
require_relative "tool_adapter"

module RedmineAiHelper
  # Namespace for MCP (Model Context Protocol) server components.
  module Mcp
    # Builds an MCP::Server instance populated with all registered BaseTools
    # subclasses, excluding SystemTools (security-sensitive admin-only tools).
    #
    # @example
    #   server = Server.build
    #   transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
    class Server
      # Tool provider class names excluded from MCP exposure (admin-only tools).
      EXCLUDED_TOOL_CLASS_NAMES = ["RedmineAiHelper::Tools::SystemTools"].freeze

      class << self
        # Builds and returns a configured MCP::Server with all available tools.
        #
        # @return [MCP::Server] server instance with all non-system tools registered
        def build
          mcp_tools = collect_tools

          MCP::Server.new(
            name: "redmine-ai-helper",
            version: plugin_version,
            instructions: "Redmine AI Helper MCP Server. All tools respect Redmine permissions.",
            tools: mcp_tools
          )
        end

        private

        # Eagerly loads all tool files so BaseTools.subclasses is complete.
        # Tools are autoloaded lazily in development/test; calling this ensures
        # all subclasses are registered before we enumerate them.
        def load_all_tool_files
          tools_dir = File.expand_path("../../tools", __FILE__)
          Dir[File.join(tools_dir, "*.rb")].each { |f| require f }
        end

        # Collects and adapts all BaseTools subclasses (excluding SystemTools)
        # into MCP::Tool subclasses.
        #
        # @return [Array<Class>] array of MCP::Tool subclasses
        def collect_tools
          load_all_tool_files
          tools = []
          RedmineAiHelper::BaseTools.subclasses.each do |base_tools_class|
            next if base_tools_class.name.nil?
            next if EXCLUDED_TOOL_CLASS_NAMES.include?(base_tools_class.name)

            base_tools_class.tool_classes.each do |ruby_tool_class|
              tools << ToolAdapter.adapt(ruby_tool_class)
            rescue => e
              Rails.logger.error("McpServerBuilder: failed to adapt tool #{ruby_tool_class.name}: #{e.message}")
            end
          end
          tools
        end

        # Returns the plugin version string.
        #
        # @return [String] plugin version
        def plugin_version
          Redmine::Plugin.find(:redmine_ai_helper).version
        rescue
          "0.0.0"
        end
      end
    end

    # @deprecated Use {Server} directly.
    McpServerBuilder = Server
  end
end
