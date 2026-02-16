# frozen_string_literal: true
require_relative "../base_agent"

module RedmineAiHelper
  module Agents
    # IssueUpdateAgent is a specialized agent for handling Redmine issue updates.
    class IssueUpdateAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("issue_update_agent/backstory")
        content = prompt.format(issue_properties: issue_properties)
        content
      end

      # Get available RubyLLM::Tool subclasses for this agent
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_providers
        [
          RedmineAiHelper::Tools::IssueTools,
          RedmineAiHelper::Tools::IssueUpdateTools,
          RedmineAiHelper::Tools::ProjectTools,
          RedmineAiHelper::Tools::UserTools,
        ]
      end

      private

      def issue_properties
        return "" unless @project
        provider = RedmineAiHelper::Tools::IssueTools.new
        properties = provider.capable_issue_properties(project_id: @project.id)
        content = <<~EOS

          ----

          The following issue properties are available for Project ID: #{@project.id}.

          ```json
          #{JSON.pretty_generate(properties)}
          ```
        EOS
        content
      end
    end
  end
end
