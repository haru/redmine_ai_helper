# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/issue_json"
require "redmine_ai_helper/util/attachment_file_helper"

module RedmineAiHelper
  module Tools
    # IssueTools is a specialized tool provider for handling Redmine issue-related queries.
    class IssueTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::IssueJson
      define_function :read_issues, description: "Read an issue from the database and return it as a JSON object. It returns the issue ID, subject, project, tracker, status, priority, author, assigned_to, description, start_date, due_date, done_ratio, is_private, estimated_hours, total_estimated_hours, spent_hours, total_spent_hours, created_on, updated_on, closed_on, issue_url, attachments, children and relations." do
        property :issue_ids, type: "array", description: "The issue ID array to read.", required: true do
          item type: "integer", description: "The issue ID to read."
        end
      end
      # Read an issue from the database.
      # @param issue_ids [Array<Integer>] The issue ID array to read.
      # @return [Hash] A hash containing issue information.
      def read_issues(issue_ids:)
        raise("Issue ID array is required.") if issue_ids.empty?
        issues = []
        Issue.where(id: issue_ids).each do |issue|

          # Check if the issue is visible to the current user
          next unless issue.visible?

          issues << generate_issue_data(issue)
        end

        raise("Issue not found") if issues.empty?

        { issues: issues }
      end

      define_function :capable_issue_properties, description: "Return properties that can be assigned to an issue for the specified project, such as status, tracker, custom fields, etc. You must specify one of project_id, project_name, or project_identifier." do
        property :project_id, type: "integer", description: "The project ID of the project to return.", required: false
        property :project_name, type: "string", description: "The project name of the project to return.", required: false
        property :project_identifier, type: "string", description: "The project identifier of the project to return.", required: false
      end
      # Return properties that can be assigned to an issue for the specified project, such as status, tracker, custom fields, etc.
      # @param project_id [Integer] The project ID of the project to return.
      # @param project_name [String] The project name of the project to return.
      # @param project_identifier [String] The project identifier of the project to return.
      # @return [Hash] A hash containing issue properties.
      def capable_issue_properties(project_id: nil, project_name: nil, project_identifier: nil)
        project = nil
        if project_id
          project = Project.find_by(id: project_id)
        elsif project_name
          project = Project.find_by(name: project_name)
        elsif project_identifier
          project = Project.find_by(identifier: project_identifier)
        else
          raise("No id or name or Identifier specified.")
        end

        raise("Project not found.") unless project

        properties = {
          trackers: project.trackers.map do |tracker|
            {
              id: tracker.id,
              name: tracker.name,
            }
          end,
          statuses: IssueStatus.all.map do |status|
            {
              id: status.id,
              name: status.name,
            }
          end,
          priorities: IssuePriority.all.map do |priority|
            {
              id: priority.id,
              name: priority.name,
            }
          end,
          categories: project.issue_categories.map do |category|
            {
              id: category.id,
              name: category.name,
            }
          end,
          versions: project.versions.map do |version|
            {
              id: version.id,
              name: version.name,
            }
          end,
          issue_custom_fields: project.issue_custom_fields.map do |field|
            {
              id: field.id,
              name: field.name,
              type: field.field_format,
              possible_values: field.possible_values,
              is_required: field.is_required,
            }
          end,
        }

        properties
      end

      define_function :validate_new_issue, description: "Validate the parameters for creating a new issue. It can be used to check if the parameters are correct before creating a new issue." do
        property :project_id, type: "integer", description: "The project ID of the project to create the issue in.", required: true
        property :tracker_id, type: "integer", description: "The tracker ID of the issue to create.", required: true
        property :subject, type: "string", description: "The subject of the issue to create.", required: true
        property :status_id, type: "integer", description: "The status ID of the issue to create.", required: true
        property :priority_id, type: "integer", description: "The priority ID of the issue to create.", required: false
        property :category_id, type: "integer", description: "The category ID of the issue to create.", required: false
        property :version_id, type: "integer", description: "The version ID of the issue to create.", required: false
        property :assigned_to_id, type: "integer", description: "The assigned_to ID of the issue to create.", required: false
        property :description, type: "string", description: "The description of the issue to create.", required: false
        property :start_date, type: "string", description: "The start date of the issue to create.", required: false
        property :due_date, type: "string", description: "The due date of the issue to create.", required: false
        property :done_ratio, type: "integer", description: "The done ratio of the issue to create.", required: false
        property :is_private, type: "boolean", description: "Whether the issue is private or not. Default is false."
        property :estimated_hours, type: "string", description: "The estimated hours of the issue to create.", required: false
        property :custom_fields, type: "array", description: "Custom fields for the new issue." do
          item type: "object", description: "The custom field of the issue to create." do
            property :field_id, type: "integer", description: "The field ID of the custom field.", required: true
            property :value, type: "string", description: "The value of the custom field.", required: true
          end
        end
      end
      # Validate the parameters for creating a new issue
      # @param project_id [Integer] The project ID of the project to create the issue in.
      # @param tracker_id [Integer] The tracker ID of the issue to create.
      # @param subject [String] The subject of the issue to create.
      # @param status_id [Integer] The status ID of the issue to create.
      # @param priority_id [Integer] The priority ID of the issue to create.
      # @param category_id [Integer] The category ID of the issue to create.
      # @param version_id [Integer] The version ID of the issue to create.
      # @param assigned_to_id [Integer] The assigned_to ID of the issue to create.
      # @param description [String] The description of the issue to create.
      # @param start_date [String] The start date of the issue to create.
      # @param due_date [String] The due date of the issue to create.
      # @param done_ratio [Integer] The done ratio of the issue to create.
      # @param is_private [Boolean] Whether the issue is private or not. Default is false.
      # @param estimated_hours [String] The estimated hours of the issue to create.
      # @param custom_fields [Array<Hash>] The custom fields of the issue to create.
      # @return [Hash] A hash containing the validation result.
      def validate_new_issue(project_id:, tracker_id:, subject:, status_id:, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [])
        issue_update_provider = IssueUpdateTools.new
        return issue_update_provider.create_new_issue(project_id: project_id, tracker_id: tracker_id, subject: subject, status_id: status_id, priority_id: priority_id, category_id: category_id, version_id: version_id, assigned_to_id: assigned_to_id, description: description, start_date: start_date, due_date: due_date, done_ratio: done_ratio, is_private: is_private, estimated_hours: estimated_hours, custom_fields: custom_fields, validate_only: true)
      end

      define_function :validate_update_issue, description: "Validate the parameters for updating an issue. It can be used to check if the parameters are correct before updating an issue." do
        property :issue_id, type: "integer", description: "The issue ID of the issue to update.", required: true
        property :subject, type: "string", description: "The subject of the issue to update.", required: false
        property :tracker_id, type: "integer", description: "The tracker ID of the issue to update.", required: false
        property :status_id, type: "integer", description: "The status ID of the issue to update.", required: false
        property :priority_id, type: "integer", description: "The priority ID of the issue to update.", required: false
        property :category_id, type: "integer", description: "The category ID of the issue to update.", required: false
        property :version_id, type: "integer", description: "The version ID of the issue to update.", required: false
        property :assigned_to_id, type: "integer", description: "The assigned_to ID of the issue to update.", required: false
        property :description, type: "string", description: "The description of the issue to update.", required: false
        property :start_date, type: "string", description: "The start date of the issue to update.", required: false
        property :due_date, type: "string", description: "The due date of the issue to update.", required: false
        property :done_ratio, type: "integer", description: "The done ratio of the issue to update.", required: false
        property :is_private, type: "boolean", description: "Whether the issue is private or not. Default is false."
        property :estimated_hours, type: "string", description: "The estimated hours of the issue to update.", required: false
        property :custom_fields, type: "array", description: "The custom fields of the issue to update.", required: false do
          item type: "object", description: "The custom field of the issue to update." do
            property :field_id, type: "integer", description: "The field ID of the custom field.", required: true
            property :value, type: "string", description: "The value of the custom field.", required: true
          end
        end
        property :comment_to_add, type: "string", description: "Comment to add to the issue. To insert a newline, you need to insert a blank line. Otherwise, it will be concatenated into a single line.", required: false
      end
      # Validate the parameters for updating an issue
      # @param issue_id [Integer] The issue ID of the issue to update.
      # @param subject [String] The subject of the issue to update.
      # @param tracker_id [Integer] The tracker ID of the issue to update.
      # @param status_id [Integer] The status ID of the issue to update.
      # @param priority_id [Integer] The priority ID of the issue to update.
      # @param category_id [Integer] The category ID of the issue to update.
      # @param version_id [Integer] The version ID of the issue to update.
      # @param assigned_to_id [Integer] The assigned_to ID of the issue to update.
      # @param description [String] The description of the issue to update.
      # @param start_date [String] The start date of the issue to update.
      # @param due_date [String] The due date of the issue to update.
      # @param done_ratio [Integer] The done ratio of the issue to update.
      # @param is_private [Boolean] Whether the issue is private or not. Default is false.
      # @param estimated_hours [String] The estimated hours of the issue to update.
      # @param custom_fields [Array<Hash>] The custom fields of the issue to update.
      # @param comment_to_add [String] Comment to add to the issue. To insert a newline, you need to insert a blank line. Otherwise, it will be concatenated into a single line.
      # @return [Hash] A hash containing the validation result.
      def validate_update_issue(issue_id:, subject: nil, tracker_id: nil, status_id: nil, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [], comment_to_add: nil)
        issue_update_provider = IssueUpdateTools.new
        return issue_update_provider.update_issue(issue_id: issue_id, subject: subject, tracker_id: tracker_id, status_id: status_id, priority_id: priority_id, category_id: category_id, version_id: version_id, assigned_to_id: assigned_to_id, description: description, start_date: start_date, due_date: due_date, done_ratio: done_ratio, is_private: is_private, estimated_hours: estimated_hours, custom_fields: custom_fields, comment_to_add: comment_to_add, validate_only: true)
      end
    end
  end
end
