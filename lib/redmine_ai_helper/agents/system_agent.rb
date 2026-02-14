# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # SystemAgent is a specialized agent for handling Redmine system-related queries.
    class SystemAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("system_agent/backstory")
        content = prompt.format
        content
      end

      # Get available RubyLLM::Tool subclasses for this agent
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_classes
        RedmineAiHelper::Tools::SystemTools.tool_classes
      end
    end
  end
end
