# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # FileAgent is a specialized agent for analyzing files attached to Redmine content.
    # It uses FileTools to analyze files (images, PDFs, documents, code, audio)
    # via internal LLM calls and return text descriptions.
    class FileAgent < RedmineAiHelper::BaseAgent
      # Returns the agent's backstory prompt for file analysis tasks.
      # @return [String] The formatted backstory text
      def backstory
        prompt = load_prompt("file_agent/backstory")
        prompt.format
      end

      # Returns the tool providers available to this agent.
      # @return [Array<Class>] Array containing FileTools
      def available_tool_providers
        [RedmineAiHelper::Tools::FileTools]
      end
    end
  end
end
