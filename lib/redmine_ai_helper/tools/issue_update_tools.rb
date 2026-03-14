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
        property :parent_issue_id, type: "integer", description: "The parent issue ID. When specified, the created issue becomes a child of the parent issue.", required: false
        property :relations, type: "array", description: "Relations to create between the new issue and existing issues.", required: false do
          item type: "object", description: "A relation to create." do
            property :issue_id, type: "integer", description: "The ID of the related issue.", required: true
            property :relation_type, type: "string", description: "The relation type. Valid values: relates, duplicates, duplicated, blocks, blocked, precedes, follows, copied_to, copied_from.", required: true
          end
        end
        property :validate_only, type: "boolean", description: "If true, only validate the issue and do not create it.", required: false
      end
      # Create a new issue in the database.
      def create_new_issue(project_id:, tracker_id:, subject:, status_id:, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [], parent_issue_id: nil, relations: [], validate_only: false)
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

        custom_values = {}
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

        if parent_issue_id.nil?
          ai_helper_logger.warn "parent_issue_id is nil, skipping parent assignment"
        else
          parent = Issue.find_by(id: parent_issue_id)
          raise("Parent issue not found. id = #{parent_issue_id}") unless parent
          issue.parent_issue_id = parent_issue_id
        end

        if validate_only
          validate_relations!(relations)
          unless issue.valid?
            raise("Validation failed. #{issue.errors.full_messages.join(", ")}")
          end
          return generate_issue_data(issue)
        end

        unless issue.save
          raise("Failed to create a new issue. #{issue.errors.full_messages.join(", ")}")
        end

        create_relations!(issue, relations)

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
        property :parent_issue_id, type: "integer", description: "The parent issue ID. Set to 0 to clear the parent (remove the parent-child relationship). When nil, the existing parent relationship is unchanged.", required: false
        property :relations_to_add, type: "array", description: "Relations to add between this issue and other issues.", required: false do
          item type: "object", description: "A relation to add." do
            property :issue_id, type: "integer", description: "The ID of the related issue.", required: true
            property :relation_type, type: "string", description: "The relation type. Valid values: relates, duplicates, duplicated, blocks, blocked, precedes, follows, copied_to, copied_from.", required: true
          end
        end
        property :relations_to_remove, type: "array", description: "Relations to remove between this issue and other issues. The issue_id uniquely identifies the relation to remove.", required: false do
          item type: "object", description: "A relation to remove." do
            property :issue_id, type: "integer", description: "The ID of the related issue whose relation should be removed.", required: true
          end
        end
        property :comment_to_add, type: "string", description: "Comment to add to the issue. To insert a newline, you need to insert a blank line. Otherwise, it will be concatenated into a single line.", required: false
        property :validate_only, type: "boolean", description: "If true, only validate the issue and do not update it.", required: false
      end
      # Update an issue in the database.
      def update_issue(issue_id:, subject: nil, tracker_id: nil, status_id: nil, priority_id: nil, category_id: nil, version_id: nil, assigned_to_id: nil, description: nil, start_date: nil, due_date: nil, done_ratio: nil, is_private: false, estimated_hours: nil, custom_fields: [], parent_issue_id: nil, relations_to_add: [], relations_to_remove: [], comment_to_add: nil, validate_only: false)
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

        custom_field_values = issue.custom_field_values.each_with_object({}) do |cf_value, hash|
          hash[cf_value.custom_field_id] = cf_value.value
        end

        custom_fields.each do |field|
          if field[:field_id].nil?
            ai_helper_logger.warn "Skipping custom field with nil field_id"
            next
          end
          custom_field = CustomField.find_by(id: field[:field_id])
          next unless custom_field
          custom_field_values[custom_field.id] = field[:value]
        end

        issue.custom_field_values = custom_field_values unless custom_field_values.empty?

        unless parent_issue_id.nil?
          if parent_issue_id == 0
            issue.parent_issue_id = nil
          else
            parent = Issue.find_by(id: parent_issue_id)
            raise("Parent issue not found. id = #{parent_issue_id}") unless parent
            issue.parent_issue_id = parent_issue_id
          end
        end

        if validate_only
          validate_relations!(relations_to_add)
          unless issue.valid?
            raise("Validation failed. #{issue.errors.full_messages.join(", ")}")
          end
          return generate_issue_data(issue)
        end

        unless issue.save
          raise("Failed to update the issue #{issue.id}. #{issue.errors.full_messages.join(", ")}")
        end

        (relations_to_remove || []).each do |rel|
          next if rel[:issue_id].nil?
          relation = issue.relations.find { |r| r.issue_from_id == rel[:issue_id] || r.issue_to_id == rel[:issue_id] }
          relation&.destroy
        end

        create_relations!(issue, relations_to_add)

        generate_issue_data(issue)
      end

      private

      # Validates that each relation entry references an existing issue and a valid relation_type.
      # Used in validate_only paths where the issue is not yet saved.
      def validate_relations!(relations)
        (relations || []).each do |rel|
          next if rel[:issue_id].nil?
          raise("Related issue not found. id = #{rel[:issue_id]}") unless Issue.exists?(rel[:issue_id])
          raise("Invalid relation_type: #{rel[:relation_type]}") unless IssueRelation::TYPES.key?(rel[:relation_type])
        end
      end

      # Creates IssueRelation records between issue and each entry in relations_list.
      # Skips entries with nil issue_id (with warning) and duplicate relations (idempotent).
      def create_relations!(issue, relations_list)
        (relations_list || []).each do |rel|
          if rel[:issue_id].nil?
            ai_helper_logger.warn "Skipping relation with nil issue_id"
            next
          end
          target = Issue.find_by(id: rel[:issue_id])
          raise("Related issue not found. id = #{rel[:issue_id]}") unless target
          raise("Invalid relation_type: #{rel[:relation_type]}") unless IssueRelation::TYPES.key?(rel[:relation_type])
          next if issue.relations.any? { |r| r.issue_from_id == rel[:issue_id] || r.issue_to_id == rel[:issue_id] }
          IssueRelation.create!(issue_from_id: issue.id, issue_to_id: rel[:issue_id], relation_type: rel[:relation_type])
        end
      end
    end
  end
end
