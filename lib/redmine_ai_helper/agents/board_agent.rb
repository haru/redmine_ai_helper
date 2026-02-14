require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # BoardAgent is a specialized agent for handling Redmine board-related queries.
    class BoardAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("board_agent/backstory")
        content = prompt.format
        content
      end

      # Get available RubyLLM::Tool subclasses for this agent
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_providers
        [RedmineAiHelper::Tools::BoardTools]
      end
    end
  end
end
