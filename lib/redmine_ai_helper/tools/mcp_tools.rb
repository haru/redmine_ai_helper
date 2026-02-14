module RedmineAiHelper
  # Tools namespace for agent capabilities
  module Tools
    # MCP (Model Context Protocol) tools integration via ruby_llm-mcp.
    # Since ruby_llm-mcp client.tools returns RubyLLM::MCP::Tool instances
    # that are already RubyLLM::Tool compatible, this class simply caches
    # and returns those tool instances directly.
    class McpTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Logger

      class << self
        # Return MCP tools directly from the client.
        # @param mcp_server_name [String] MCP server name
        # @param mcp_client [RubyLLM::MCP::Client] MCP client instance
        # @return [Array<RubyLLM::MCP::Tool>] array of tool instances
        def generate_tool_classes(mcp_server_name:, mcp_client:)
          @mcp_tool_cache ||= {}
          @mcp_tool_cache[mcp_server_name] ||= begin
            tools = mcp_client.tools
            RedmineAiHelper::CustomLogger.instance.info "Loaded #{tools.size} tools from MCP server '#{mcp_server_name}'"
            tools
          rescue => e
            RedmineAiHelper::CustomLogger.instance.error "Error loading tools from MCP server '#{mcp_server_name}': #{e.message}"
            RedmineAiHelper::CustomLogger.instance.error e.backtrace.join("\n")
            []
          end
        end
      end
    end
  end
end
