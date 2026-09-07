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
        !!(project&.id && user.allowed_to?(permission, project))
      end

      # Check whether AI Helper may read/update the given project's data for the given user
      # (the "data access" decision, as opposed to {module_enabled?}'s UI-visibility decision).
      # This is the single source of truth shared by every tool/agent that reaches across
      # projects (see contracts/data-access-scope.md in specs/057-all-projects-scope).
      # Decision table:
      #   - project nil/unsaved, or not visible to user -> false
      #   - ai_helper module enabled -> user.allowed_to?(:view_ai_helper, project)
      #   - ai_helper module disabled -> all_projects_scope
      # @param project [Project, nil] The project to check
      # @param user [User] The user to check permissions for (default User.current)
      # @param all_projects_scope [Boolean] Whether the all-projects data-access scope
      #   setting is enabled. Callers looping over many projects should read
      #   AiHelperSetting.all_projects_scope? once and pass it here to avoid N+1 reads.
      # @return [Boolean] true if the project's data is accessible to the user
      def self.data_accessible?(project:, user: User.current, all_projects_scope: AiHelperSetting.all_projects_scope?)
        return false unless project&.id && project.visible?(user)
        return user.allowed_to?(:view_ai_helper, project) if project.module_enabled?(:ai_helper)
        all_projects_scope
      end

      # SQL condition (for the `projects` table) selecting projects whose data is accessible
      # to the given user, for use in cross-project queries. The caller's relation must already
      # apply data-type visibility (e.g. Issue.visible(user)), which covers project visibility
      # and state; this condition only decides the ai_helper module / all_projects_scope part.
      # @param user [User] The user to check permissions for (default User.current)
      # @param all_projects_scope [Boolean] Whether the all-projects data-access scope
      #   setting is enabled (default AiHelperSetting.all_projects_scope?)
      # @return [String] SQL condition string safe to pass to `where`
      def self.data_access_condition(user = User.current, all_projects_scope: AiHelperSetting.all_projects_scope?)
        condition = Project.allowed_to_condition(user, :view_ai_helper)
        return condition unless all_projects_scope
        "((#{condition}) OR NOT EXISTS (SELECT 1 FROM #{EnabledModule.table_name} em" \
          " WHERE em.project_id = #{Project.table_name}.id AND em.name = 'ai_helper'))"
      end
    end
  end
end
