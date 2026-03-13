# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/issue_json"

module RedmineAiHelper
  module Tools
    # IssueUpdateTools is a specialized tool for handling Redmine issue updates.
    class IssueUpdateTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::IssueJson
      define_function :create_new_issue, description: "Create a new issue in the database." do
        property :project_id, type: "integer", description: "The project ID of the issue to create.", required: true
        property :tracker_id, type: "integer", description: "The tracker ID of the issue to create.", required: true
        property :subject, type: "string", description: "The subject of the issue to create.", required: true
        property :status_id, type: "integer", description: "The status ID of the issue to create.", required: true
        property :priority_id, type: "integer", description: "The priority ID of the issue to create.", required: false
        property :category_id, type: "integer", description: "The category ID of the issue to create.", required: false
        property :version_id, type: "integer", description: "The version ID of the issue to create.", required: false
        property :assigned_to_id, type: "integer", description: "The assigned to ID of the issue to create.", required: false
        property :description, type: "string", description: "The description of the issue to create.", required: false
        property :start_date, type: "string", description: "The start date of the issue to create.", required: false
        property :due_date, type: "string", description: "The due date of the issue to create.", required: false
        property :done_ratio, type: "integer", description: "The done ratio of the issue to create.", required: false
        property :is_private, type: "boolean", description: "The is_private of the issue to create.", required: false
        property :estimated_hours, type: "string", description: "The estimated hours of the issue to create.", required: false
        property :custom_fields, type: "array", description: "The custom fields of the issue to create.", required: false do
          item type: "object", description: "The custom field of the issue to create." do
            property :field_id, type: "integer", description: "The field ID of the custom field.", required: true
            property :value, type: "string", description: "The value of the custom field.", required: true
          end
        end
        property :validate_only, type: "boolean", description: "If true, only validate the issue and do not create it.", required: false
      end
      # Create a new issue in the database.
      def create_new_issue(project_id:, tracker_id:, subject:, status_id:, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [], validate_only: false)
        project = Project.find_by(id: project_id)
        raise("Project not found. id = #{project_id}") unless project
        raise("Permission denied") unless User.current.allowed_to?(:add_issues, project)

        issue = Issue.new
        issue.project_id = project_id
        issue.author_id = User.current.id
        issue.tracker_id = tracker_id
        issue.subject = subject
        issue.status_id = status_id
        issue.priority_id = priority_id if priority_id
        issue.category_id = category_id if category_id
        issue.fixed_version_id = version_id if version_id
        issue.assigned_to_id = assigned_to_id if assigned_to_id
        issue.description = description
        issue.start_date = start_date
        issue.due_date = due_date
        issue.done_ratio = done_ratio
        issue.is_private = is_private
        issue.estimated_hours = estimated_hours.to_f if estimated_hours

        custom_values = issue.custom_field_values || {}
        custom_fields.each do |field|
          if field[:field_id].nil?
            ai_helper_logger.warn "Skipping custom field with nil field_id"
            next
          end
          custom_field = CustomField.find_by(id: field[:field_id])
          next unless custom_field
          custom_values[custom_field.id] = field[:value]
        end
        issue.custom_field_values = custom_values unless custom_values.empty?

        if validate_only
          unless issue.valid?
            raise("Validation failed. #{issue.errors.full_messages.join(", ")}")
          end
          return generate_issue_data(issue)
        end
        unless issue.save
          raise("Failed to create a new issue. #{issue.errors.full_messages.join(", ")}")
        end
        generate_issue_data(issue)
      end

      define_function :update_issue, description: "Update an issue in the database." do
        property :issue_id, type: "integer", description: "The issue ID of the issue to update.", required: true
        property :subject, type: "string", description: "The subject of the issue to update.", required: false
        property :tracker_id, type: "integer", description: "The tracker ID of the issue to update.", required: false
        property :status_id, type: "integer", description: "The status ID of the issue to update.", required: false
        property :priority_id, type: "integer", description: "The priority ID of the issue to update.", required: false
        property :category_id, type: "integer", description: "The category ID of the issue to update.", required: false
        property :version_id, type: "integer", description: "The version ID of the issue to update.", required: false
        property :assigned_to_id, type: "integer", description: "The assigned to ID of the issue to update.", required: false
        property :description, type: "string", description: "The description of the issue to update.", required: false
        property :start_date, type: "string", description: "The start date of the issue to update.", required: false
        property :due_date, type: "string", description: "The due date of the issue to update.", required: false
        property :done_ratio, type: "integer", description: "The done ratio of the issue to update.", required: false
        property :is_private, type: "boolean", description: "The is_private of the issue to update.", required: false
        property :estimated_hours, type: "string", description: "The estimated hours of the issue to update.", required: false
        property :custom_fields, type: "array", description: "The custom fields of the issue to update.", required: false do
          item type: "object", description: "The custom field of the issue to update." do
            property :field_id, type: "integer", description: "The field ID of the custom field.", required: true
            property :value, type: "string", description: "The value of the custom field.", required: true
          end
        end
        property :comment_to_add, type: "string", description: "Comment to add to the issue. To insert a newline, you need to insert a blank line. Otherwise, it will be concatenated into a single line.", required: false
        property :validate_only, type: "boolean", description: "If true, only validate the issue and do not update it.", required: false
      end
      # Update an issue in the database.
      def update_issue(issue_id:, subject: nil, tracker_id: nil, status_id: nil, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [], comment_to_add: nil, validate_only: false)
        issue = Issue.find_by(id: issue_id)
        raise("Issue not found. id = #{issue_id}") unless issue
        raise("Permission denied") unless issue.editable?(User.current)

        if comment_to_add
          issue.init_journal(User.current, comment_to_add)
        else
          issue.init_journal(User.current)
        end

        issue.subject = subject if subject
        issue.tracker_id = tracker_id if tracker_id
        issue.status_id = status_id if status_id
        issue.priority_id = priority_id if priority_id
        issue.category_id = category_id if category_id
        issue.fixed_version_id = version_id if version_id
        issue.assigned_to_id = assigned_to_id if assigned_to_id
        issue.description = description if description
        issue.start_date = start_date if start_date
        issue.due_date = due_date if due_date
        issue.done_ratio = done_ratio if done_ratio
        issue.is_private = is_private if is_private
        issue.estimated_hours = estimated_hours.to_f if estimated_hours

        custom_fields.each do |field|
          if field[:field_id].nil?
            ai_helper_logger.warn "Skipping custom field with nil field_id"
            next
          end
          custom_field = CustomField.find_by(id: field[:field_id])
          next unless custom_field
          issue.custom_field_values = { custom_field.id => field[:value] }
        end

        if validate_only
          unless issue.valid?
            raise("Validation failed. #{issue.errors.full_messages.join(", ")}")
          end
          return generate_issue_data(issue)
        end

        unless issue.save
          raise("Failed to update the issue #{issue.id}. #{issue.errors.full_messages.join(", ")}")
        end
        generate_issue_data(issue)
      end

      private
    end
  end
end
