require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    class ImageAgent < RedmineAiHelper::BaseAgent
      def backstory
        prompt = load_prompt("image_agent/backstory")
        prompt.format
      end

      def available_tool_providers
        [RedmineAiHelper::Tools::ImageTools]
      end
    end
  end
end
