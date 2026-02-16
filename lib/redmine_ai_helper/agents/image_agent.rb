require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # ImageAgent is a specialized agent for analyzing images attached to Redmine content.
    # It uses ImageTools to analyze images via internal LLM calls and return text descriptions.

    class ImageAgent < RedmineAiHelper::BaseAgent
      # Returns the agent's backstory prompt for image analysis tasks.
      # @return [String] The formatted backstory text
      def backstory
        prompt = load_prompt("image_agent/backstory")
        prompt.format
      end

      # Returns the tool providers available to this agent.
      # @return [Array<Class>] Array containing ImageTools
      def available_tool_providers
        [RedmineAiHelper::Tools::ImageTools]
      end
    end
  end
end
