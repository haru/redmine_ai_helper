# frozen_string_literal: true

require_relative "../base_agent"
require "redmine_ai_helper/tools/dmsf_tools"

module RedmineAiHelper
  module Agents
    # Dedicated read-only agent for DMSF document discovery and analysis.
    # BaseAgent registers this agent automatically; AgentList hides it if disabled.
    class DmsfAgent < RedmineAiHelper::BaseAgent
      # @return [Boolean] true when DMSF is present and attachment sharing opted in
      delegate :enabled?, to: :'RedmineAiHelper::Tools::DmsfTools'

      # @return [String] Instructions for querying DMSF safely
      def backstory
        load_prompt("dmsf_agent/backstory").format
      end

      # @return [Array<Class>] Read-only DMSF tool provider
      def available_tool_providers
        [ RedmineAiHelper::Tools::DmsfTools ]
      end
    end
  end
end
