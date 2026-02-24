# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Utility class for checking AI Helper module permissions on projects.
    class PermissionChecker
      # Check if the AI Helper module is enabled and accessible for the given project and user.
      # Returns true only when:
      # - project exists and is persisted (has an id)
      # - user has the specified permission on the project
      #   (allowed_to? internally checks module_enabled? as well)
      def self.module_enabled?(project:, user: User.current, permission: :view_ai_helper)
        project&.id && user.allowed_to?(permission, project)
      end
    end
  end
end
