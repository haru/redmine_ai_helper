# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # RepositoryAgent is a specialized agent for handling Redmine repository-related queries.
    class RepositoryAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("repository_agent/backstory")
        content = prompt.format
        content
      end

      # Get available tool providers for this agent
      # @return [Array<Class>] Array of tool provider classes
      def available_tool_providers
        [RedmineAiHelper::Tools::RepositoryTools]
      end
    end
  end
end
