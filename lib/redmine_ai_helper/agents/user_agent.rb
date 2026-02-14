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

      # Get available RubyLLM::Tool subclasses for this agent
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_classes
        RedmineAiHelper::Tools::UserTools.tool_classes
      end
    end
  end
end
