# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # VersionAgent is a specialized agent for handling Redmine version-related queries.
    class VersionAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("version_agent/backstory")
        content = prompt.format
        content
      end

      # Get available tool providers for this agent
      # @return [Array<Class>] Array of tool provider classes
      def available_tool_providers
        [RedmineAiHelper::Tools::VersionTools]
      end
    end
  end
end
