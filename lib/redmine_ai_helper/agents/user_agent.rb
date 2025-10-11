# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # UserAgent is a specialized agent for handling Redmine user-related queries.
    class UserAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("user_agent/backstory")
        content = prompt.format
        content
      end

      # Get available tool providers for this agent
      # @return [Array<Class>] Array of tool provider classes
      def available_tool_providers
        [RedmineAiHelper::Tools::UserTools]
      end
    end
  end
end
