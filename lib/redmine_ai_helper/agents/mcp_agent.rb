module RedmineAiHelper
  module Agents
    class McpAgent < RedmineAiHelper::BaseAgent
      include RedmineAiHelper::Logger

      def role
        "mcp_agent"
      end

      def backstory
        prompt = load_prompt("mcp_agent/backstory")
        content = prompt.format
        content
      end

      # McpAgent base class is not used as an actual agent
      def enabled?
        false
      end
    end
  end
end