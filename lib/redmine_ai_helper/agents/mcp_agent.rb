module RedmineAiHelper
  # Namespace for AI agents
  module Agents
    # Base MCP agent for Model Context Protocol integration
    class McpAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Logger

      # Get the agent's role
      # @return [String] The role identifier
      def role
        "mcp_agent"
      end

      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        # Base (abstract) McpAgent: supply only variables required by the template.
        prompt = load_prompt("mcp_agent/backstory")
        # Langchain::Prompt exposes input_variables
        if prompt.respond_to?(:input_variables) && prompt.input_variables.include?("server_name")
          prompt.format(server_name: "generic")
        else
          prompt.format
        end
      end

      # McpAgent base class is not used as an actual agent
      def enabled?
        false
      end
    end
  end
end