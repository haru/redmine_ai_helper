# frozen_string_literal: true
require "langchain"
require "redmine_ai_helper/logger"

module RedmineAiHelper

  # Base class for all tools.
  class BaseTools
    extend Langchain::ToolDefinition

    include RedmineAiHelper::Logger
    include Rails.application.routes.url_helpers

    # Check if the specified project is accessible
    # @param project [Project] The project
    # @return [Boolean] true if accessible, false otherwise
    def accessible_project?(project)
      return false unless project.visible?
      return false unless project.module_enabled?(:ai_helper)
      User.current.allowed_to?({ controller: :ai_helper, action: :chat_form }, project)
    end
  end
end
