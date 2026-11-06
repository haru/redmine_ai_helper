# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/project_write_guard"
require "redmine_ai_helper/util/member_hash"

module RedmineAiHelper
  module Tools
    # CategoryTools provides issue category operations for a project: listing
    # the categories with the principals that can be assigned, creating a
    # category, and updating its name and default assignee. No delete operation
    # exists on purpose (FR-002).
    class CategoryTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::ProjectWriteGuard
      include RedmineAiHelper::Util::MemberHash

      define_function :list_categories, description: "List the issue categories of a project and the users or groups that can be set as a category assignee. The issue_tracking module must be enabled on the project." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
      end
      # List the issue categories and the assignable principals of a project.
      # @param project_id [Integer] The project ID.
      # @return [Hash] { project_id:, categories: [ { id:, name:, assigned_to: } ],
      #   assignable_principals: [ { id:, name:, type: } ] }, or { error: } for a
      #   user-caused failure.
      def list_categories(project_id:)
        user_errors_as_result do
          project = readable_project!(project_id: project_id, permission: nil, require_issue_tracking: true)

          {
            project_id: project.id,
            categories: project.issue_categories.order(:id).map { |category| category_summary(category) },
            assignable_principals: project.assignable_users.map { |principal| principal_summary(principal) }
          }
        end
      end

      define_function :create_category, write: true, description: "Create an issue category in a project, optionally with a default assignee. The assignee must be in the assignable_principals of list_categories. Category names must be unique within the project." do
        property :project_id, type: "integer", description: "The ID of the project.", required: true
        property :name, type: "string", description: "The category name.", required: true
        property :assigned_to_id, type: "integer", description: "The ID of the user or group to assign new issues of this category to by default.", required: false
      end
      # Create an issue category.
      # @param project_id [Integer] The project ID.
      # @param name [String] The category name.
      # @param assigned_to_id [Integer, nil] The default assignee ID.
      # @return [Hash] The Category hash, or { error: } for a user-caused failure.
      def create_category(project_id:, name:, assigned_to_id: nil)
        user_errors_as_result do
          project = writable_project!(
            project_id: project_id, permission: :manage_categories, require_issue_tracking: true
          )
          validate_assignee!(project, assigned_to_id)

          category = project.issue_categories.build(name: name, assigned_to_id: assigned_to_id)
          unless category.save
            raise UserError, "Failed to create category: #{category.errors.full_messages.join(", ")}"
          end

          category_to_hash(category)
        end
      end

      define_function :update_category, write: true, description: "Update the name or the default assignee of an existing issue category. Only the given fields are changed. Use clear_assigned_to to remove the assignee (it cannot be combined with assigned_to_id)." do
        property :category_id, type: "integer", description: "The ID of the category. Use list_categories to look it up.", required: true
        property :name, type: "string", description: "The new category name.", required: false
        property :assigned_to_id, type: "integer", description: "The ID of the new default assignee. Must be in the assignable_principals of list_categories.", required: false
        property :clear_assigned_to, type: "boolean", description: "Set to true to remove the default assignee.", required: false
      end
      # Update an issue category. Fields that are nil are left unchanged.
      # @param category_id [Integer] The category ID.
      # @param name [String, nil] The new name.
      # @param assigned_to_id [Integer, nil] The new default assignee ID.
      # @param clear_assigned_to [Boolean, nil] true to remove the assignee.
      # @return [Hash] The Category hash, or { error: } for a user-caused failure.
      def update_category(category_id:, name: nil, assigned_to_id: nil, clear_assigned_to: nil)
        user_errors_as_result do
          category = IssueCategory.find_by(id: category_id)
          # A category of a project the caller cannot see is reported as not found,
          # so neither its existence nor its project id leaks.
          raise UserError, "Category not found. id = #{category_id}" if category.nil? || !category.project.visible?

          project = writable_project!(
            project_id: category.project_id, permission: :manage_categories, require_issue_tracking: true
          )
          validate_booleans!("clear_assigned_to" => clear_assigned_to)
          if !assigned_to_id.nil? && clear_assigned_to == true
            raise UserError, "assigned_to_id and clear_assigned_to cannot be used together"
          end

          validate_assignee!(project, assigned_to_id)
          category.name = name unless name.nil?
          category.assigned_to_id = assigned_to_id unless assigned_to_id.nil?
          category.assigned_to_id = nil if clear_assigned_to == true
          next category_to_hash(category) unless category.changed?

          unless category.save
            raise UserError, "Failed to update category: #{category.errors.full_messages.join(", ")}"
          end

          category_to_hash(category)
        end
      end

      private

      # Reject an assignee that is not assignable in the project. Redmine does not
      # validate the category assignee, so the check is explicit (ADR-067).
      # @param project [Project] The project.
      # @param assigned_to_id [Integer, nil] The requested assignee ID.
      # @return [void]
      # @raise [UserError] when the principal is not in project.assignable_users.
      def validate_assignee!(project, assigned_to_id)
        return if assigned_to_id.nil?
        return if project.assignable_users.any? { |principal| principal.id == assigned_to_id }

        raise UserError, "Assignee not allowed: id = #{assigned_to_id} (must be an assignable member of the project)"
      end

      # The Category hash of contracts/category_tools.md.
      # @param category [IssueCategory] The category.
      # @return [Hash] { id:, project:, name:, assigned_to: }.
      def category_to_hash(category)
        category_summary(category).merge(project: format_named_record(category.project))
      end

      # The { id:, name:, assigned_to: } summary of a category.
      # @param category [IssueCategory] The category.
      # @return [Hash] The category summary.
      def category_summary(category)
        {
          id: category.id,
          name: category.name,
          assigned_to: category.assigned_to ? principal_summary(category.assigned_to) : nil
        }
      end

      # The { id:, name:, type: } summary of a principal.
      # @param principal [Principal] The user or group.
      # @return [Hash] The principal summary.
      def principal_summary(principal)
        { id: principal.id, name: principal.name, type: principal_type(principal) }
      end
    end
  end
end
