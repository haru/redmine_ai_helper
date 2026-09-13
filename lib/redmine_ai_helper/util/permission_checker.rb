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

      # Filter the given projects relation down to the projects whose data is accessible
      # to the user. Shared by every caller that narrows a candidate project set
      # (BaseTools#accessible_projects, IssueReadAgent#fetch_todo_issues_from_other_projects,
      # VectorTools#collect_permitted_project_ids). enabled_modules is preloaded so a large
      # instance does not issue one module query per project, and the all_projects_scope
      # flag is read once by default, avoiding an N+1 read of the settings row
      # (see contracts/data-access-scope.md in specs/057-all-projects-scope).
      # @param relation [ActiveRecord::Relation] Candidate projects (e.g. Project.visible)
      # @param user [User] The user to check permissions for (default User.current)
      # @param all_projects_scope [Boolean] Whether the all-projects data-access scope
      #   setting is enabled. Callers that already read the flag should pass it here to
      #   avoid re-reading the settings row.
      # @return [Array<Project>] The accessible projects
      def self.accessible_projects(relation, user: User.current, all_projects_scope: AiHelperSetting.all_projects_scope?)
        relation.preload(:enabled_modules).select { |project| data_accessible?(project: project, user: user, all_projects_scope: all_projects_scope) }
      end

      # SQL condition (for the `projects` table) selecting projects whose data is accessible
      # to the given user, for use in cross-project queries. The condition is self-contained:
      # it ANDs Project.visible_condition(user) (project visibility and status) with the
      # ai_helper module / all_projects_scope part, so no caller omission can widen the
      # result. A caller whose relation already applies data-type visibility (e.g.
      # Issue.visible(user)) simply ANDs the same constraints twice, which is harmless.
      # @param user [User] The user to check permissions for (default User.current)
      # @param all_projects_scope [Boolean] Whether the all-projects data-access scope
      #   setting is enabled (default AiHelperSetting.all_projects_scope?)
      # @return [String] SQL condition string safe to pass to `where`
      def self.data_access_condition(user = User.current, all_projects_scope: AiHelperSetting.all_projects_scope?)
        scoped =
          if all_projects_scope
            condition = Project.allowed_to_condition(user, :view_ai_helper)
            "((#{condition}) OR NOT EXISTS (SELECT 1 FROM #{EnabledModule.table_name} em" \
              " WHERE em.project_id = #{Project.table_name}.id AND em.name = 'ai_helper'))"
          else
            Project.allowed_to_condition(user, :view_ai_helper)
          end
        "(#{Project.visible_condition(user)}) AND (#{scoped})"
      end
    end
  end
end
