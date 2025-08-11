module RedmineAiHelper
  module Agents
    class McpAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Logger

      def role
        "mcp_agent"
      end

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