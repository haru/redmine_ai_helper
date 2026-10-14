module RedmineAiHelper
  # Tools namespace for agent capabilities
  module Tools
    # MCP (Model Context Protocol) tools integration via RubyLLM's built-in MCP client.
    # Since the client's tools method returns RubyLLM::MCP::Tool instances
    # that are already RubyLLM::Tool compatible, this class simply returns
    # those tool instances directly.
    class McpTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Logger

      class << self
        # Return MCP tools directly from the client. RubyLLM::MCP#tools memoizes the
        # list and refreshes it when the server reports a change, so no cache is kept here.
        # Connection errors are raised to the caller.
        # @param mcp_server_name [String] MCP server name
        # @param mcp_client [RubyLLM::MCP] MCP instance created by RubyLLM.mcp
        # @return [Array<RubyLLM::MCP::Tool>] array of tool instances
        def generate_tool_classes(mcp_server_name:, mcp_client:)
          tools = mcp_client.tools
          RedmineAiHelper::CustomLogger.instance.debug "Loaded #{tools.size} tools from MCP server '#{mcp_server_name}'"
          tools
        end
      end
    end
  end
end
