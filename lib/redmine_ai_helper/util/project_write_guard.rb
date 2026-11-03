# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Shared fetch of the target project for the project-management write tools
    # (ProjectWriteTools / MemberTools / CategoryTools).
    #
    # The guards run in a fixed order and raise BaseTools::UserError on the first
    # failed condition, so a user-caused failure changes nothing and reports which
    # permission or object is missing (ADR-048, data-model.md "対象プロジェクトの取得"):
    #   1. project_id given
    #   2. project exists and is visible
    #   3. project is accessible via AI Helper
    #   4. project is not closed (write fetch only; read fetch skips this)
    #   5. issue_tracking module enabled (only when required)
    #   6. the current user holds the required permission on the project
    #      (skipped when permission is nil, for reads that only need visibility)
    #
    # The including class must be a RedmineAiHelper::BaseTools (for accessible_project?
    # and UserError).
    module ProjectWriteGuard
      # Fetch the project for a write operation.
      # @param project_id [Integer, nil] The project ID.
      # @param permission [Symbol, Hash] The permission required on the project.
      # @param require_issue_tracking [Boolean] Also require the issue_tracking module
      #   (checked before the permission, matching Redmine's tracker settings tab).
      # @return [Project] The project.
      # @raise [RedmineAiHelper::BaseTools::UserError] on the first failed guard.
      def writable_project!(project_id:, permission:, require_issue_tracking: false)
        fetch_project!(project_id: project_id, permission: permission, require_issue_tracking: require_issue_tracking, closed_check: true)
      end

      # Fetch the project for a read operation. Closed projects stay readable
      # (Redmine also allows browsing a closed project), so guard 4 is skipped.
      # @param project_id [Integer, nil] The project ID.
      # @param permission [Symbol, Hash, nil] The permission required on the project;
      #   nil when visibility and AI Helper access are enough.
      # @param require_issue_tracking [Boolean] Also require the issue_tracking module.
      # @return [Project] The project.
      # @raise [RedmineAiHelper::BaseTools::UserError] on the first failed guard.
      def readable_project!(project_id:, permission:, require_issue_tracking: false)
        fetch_project!(project_id: project_id, permission: permission, require_issue_tracking: require_issue_tracking, closed_check: false)
      end

      private

      # Run the guards in order and return the project.
      # @param project_id [Integer, nil] The project ID.
      # @param permission [Symbol, Hash] The permission required on the project.
      # @param require_issue_tracking [Boolean] Whether the issue_tracking module is required.
      # @param closed_check [Boolean] Whether to reject closed projects.
      # @return [Project] The project.
      # @raise [RedmineAiHelper::BaseTools::UserError] on the first failed guard.
      def fetch_project!(project_id:, permission:, require_issue_tracking:, closed_check:)
        raise BaseTools::UserError, "project_id is required" if project_id.nil?

        project = Project.find_by(id: project_id)
        raise BaseTools::UserError, "Project not found. id = #{project_id}" if project.nil? || !project.visible?
        raise BaseTools::UserError, "Project is not accessible: id = #{project_id}" unless accessible_project?(project)
        raise BaseTools::UserError, "Project is closed: id = #{project_id}" if closed_check && project.closed?
        if require_issue_tracking && !project.module_enabled?(:issue_tracking)
          raise BaseTools::UserError, "Issue tracking module is not enabled on project #{project_id}"
        end
        if !permission.nil? && !User.current.allowed_to?(permission, project)
          raise BaseTools::UserError, "Permission denied: #{permission_name(permission)} on project #{project_id}"
        end

        project
      end

      # Render a permission for the error message the way Redmine names it.
      # @param permission [Symbol, Hash] The permission.
      # @return [String] "manage_members" or "projects/manage_members" style name.
      def permission_name(permission)
        case permission
        when Hash then permission.values.join("/")
        else permission.to_s
        end
      end
    end
  end
end
