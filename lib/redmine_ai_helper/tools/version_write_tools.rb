# frozen_string_literal: true

require "redmine_ai_helper/base_tools"

module RedmineAiHelper
  module Tools
    # VersionWriteTools provides write operations (create, update, delete) for Redmine versions.
    class VersionWriteTools < RedmineAiHelper::BaseTools
      define_function :create_version, description: "Create a new version (milestone) in a project. Requires the manage versions permission.", write: true do
        property :project_id, type: "integer", description: "The ID of the project the version belongs to.", required: true
        property :name, type: "string", description: "The version name (unique in the project, up to 60 characters).", required: true
        property :description, type: "string", description: "The description (up to 255 characters).", required: false
        property :status, type: "string", description: "The status. Defaults to open.", required: false, enum: %w[open locked closed]
        property :due_date, type: "string", description: "The due date in YYYY-MM-DD format.", required: false
        property :sharing, type: "string", description: "The sharing scope. Defaults to none. Values not allowed for the current user are rejected.", required: false, enum: %w[none descendants hierarchy tree system]
        property :wiki_page_title, type: "string", description: "The title of the related wiki page (up to 255 characters).", required: false
        property :default_project_version, type: "boolean", description: "true sets it as the project's default version; false does nothing.", required: false
        property :custom_fields, type: "array", description: "Values of the version custom fields. Use capable_version_props to see the editable ones and their possible values. A multiple-value field is set to the one given value.", required: false do
          item type: "object", description: "A custom field value." do
            property :field_id, type: "integer", description: "The custom field ID.", required: true
            property :value, type: "string", description: "The value to set.", required: false
          end
        end
      end
      # Create a new version in a project.
      # @param project_id [Integer] The project ID.
      # @param name [String] The version name.
      # @param description [String, nil] The description.
      # @param status [String, nil] The status (open, locked, closed).
      # @param due_date [String, nil] The due date (YYYY-MM-DD).
      # @param sharing [String, nil] The sharing scope.
      # @param wiki_page_title [String, nil] The related wiki page title.
      # @param default_project_version [Boolean, nil] Whether to make it the project's default version.
      # @param custom_fields [Array<Hash>, nil] Custom field values ({ field_id:, value: }).
      # @return [Hash] The created version, or { error: } for a user-caused failure.
      def create_version(project_id:, name:, description: nil, status: nil, due_date: nil, sharing: nil,
                         wiki_page_title: nil, default_project_version: nil, custom_fields: nil)
        user_errors_as_result do
          raise UserError, "project_id is required" if project_id.nil?
          raise UserError, "name is required" if name.nil?
          project = Project.find_by(id: project_id)
          raise UserError, "Project not found. id = #{project_id}" if project.nil? || !project.visible?
          raise UserError, "Project is not accessible: id = #{project_id}" unless accessible_project?(project)
          raise UserError, "Permission denied" unless User.current.allowed_to?(:manage_versions, project)

          version = project.versions.build
          custom_fields = normalize_custom_fields(custom_fields)
          validate_sharing!(version, sharing)
          validate_custom_fields!(version, custom_fields)
          version.safe_attributes = build_version_attributes(
            name: name, description: description, status: status, due_date: due_date, sharing: sharing,
            wiki_page_title: wiki_page_title, default_project_version: default_project_version, custom_fields: custom_fields
          )
          raise UserError, "Failed to create version: #{version.errors.full_messages.join(", ")}" unless version.save

          version_to_hash(version)
        end
      end

      define_function :update_version, description: "Update an existing version. Only the given attributes are changed. Pass an empty string to due_date, description, or wiki_page_title to clear it.", write: true do
        property :version_id, type: "integer", description: "The ID of the version to update.", required: true
        property :name, type: "string", description: "The new version name (unique in the project, up to 60 characters).", required: false
        property :description, type: "string", description: "The new description (up to 255 characters).", required: false
        property :status, type: "string", description: "The new status.", required: false, enum: %w[open locked closed]
        property :due_date, type: "string", description: "The new due date in YYYY-MM-DD format.", required: false
        property :sharing, type: "string", description: "The new sharing scope. Values not allowed for the current user are rejected.", required: false, enum: %w[none descendants hierarchy tree system]
        property :wiki_page_title, type: "string", description: "The title of the related wiki page (up to 255 characters).", required: false
        property :default_project_version, type: "boolean", description: "true sets it as the project's default version; false does nothing.", required: false
        property :custom_fields, type: "array", description: "Values of the version custom fields. Use capable_version_props to see the editable ones and their possible values. A multiple-value field is set to the one given value.", required: false do
          item type: "object", description: "A custom field value." do
            property :field_id, type: "integer", description: "The custom field ID.", required: true
            property :value, type: "string", description: "The value to set.", required: false
          end
        end
      end
      # Update an existing version. Attributes that are nil are left unchanged.
      # @param version_id [Integer] The version ID.
      # @param name [String, nil] The new name.
      # @param description [String, nil] The new description.
      # @param status [String, nil] The new status.
      # @param due_date [String, nil] The new due date (YYYY-MM-DD, "" to clear).
      # @param sharing [String, nil] The new sharing scope.
      # @param wiki_page_title [String, nil] The new related wiki page title.
      # @param default_project_version [Boolean, nil] Whether to make it the project's default version.
      # @param custom_fields [Array<Hash>, nil] Custom field values ({ field_id:, value: }).
      # @return [Hash] The updated version, or { error: } for a user-caused failure.
      def update_version(version_id:, name: nil, description: nil, status: nil, due_date: nil, sharing: nil,
                         wiki_page_title: nil, default_project_version: nil, custom_fields: nil)
        user_errors_as_result do
          version = find_manageable_version!(version_id)
          custom_fields = normalize_custom_fields(custom_fields)
          attrs = build_version_attributes(
            name: name, description: description, status: status, due_date: due_date, sharing: sharing,
            wiki_page_title: wiki_page_title, default_project_version: default_project_version, custom_fields: custom_fields
          )
          next version_to_hash(version) if attrs.empty?

          validate_sharing!(version, sharing)
          validate_custom_fields!(version, custom_fields)
          version.safe_attributes = attrs
          raise UserError, "Failed to update version: #{version.errors.full_messages.join(", ")}" unless version.save

          version_to_hash(version)
        end
      end

      define_function :delete_version, description: "Delete a version. Only versions that have no assigned issues, are not referenced by a version custom field, and have no attachments can be deleted. Always confirm with the user before deleting.", write: true do
        property :version_id, type: "integer", description: "The ID of the version to delete.", required: true
      end
      # Delete a version that is not in use.
      # @param version_id [Integer] The version ID.
      # @return [Hash] { deleted: true, id:, name: }, or { error: } for a user-caused failure.
      def delete_version(version_id:)
        user_errors_as_result do
          version = find_manageable_version!(version_id)
          unless version.deletable?
            issue_count = version.fixed_issues.count
            reason = if issue_count > 0
              "#{issue_count} issue(s) are assigned to it"
            elsif version.attachments.any?
              "it has attachments"
            else
              "it is referenced by a version custom field"
            end
            raise UserError, "Version is in use and cannot be deleted: #{reason}"
          end

          version.destroy!
          { deleted: true, id: version.id, name: version.name }
        end
      end

      private

      # Find a visible version and check that the current user may manage it.
      # Permission is judged on the version's own project, not on projects it is shared with.
      # @param version_id [Integer, nil] The version ID.
      # @return [Version] The version.
      # @raise [UserError] if the id is missing, the version is not found or not accessible, or permission is denied.
      def find_manageable_version!(version_id)
        raise UserError, "version_id is required" if version_id.nil?
        version = Version.find_by(id: version_id)
        raise UserError, "Version not found. id = #{version_id}" if version.nil? || !version.visible?
        raise UserError, "Project is not accessible: id = #{version.project_id}" unless accessible_project?(version.project)
        raise UserError, "Permission denied" unless User.current.allowed_to?(:manage_versions, version.project)

        version
      end

      # Build the attributes hash for Version#safe_attributes=, keeping only given values.
      # @param custom_fields [Array<Hash>] Entries already passed through {#normalize_custom_fields}.
      # @return [Hash] String-keyed attributes.
      def build_version_attributes(name: nil, description: nil, status: nil, due_date: nil, sharing: nil,
                                   wiki_page_title: nil, default_project_version: nil, custom_fields: nil)
        attrs = {
          "name" => name, "description" => description, "status" => status, "due_date" => due_date,
          "sharing" => sharing, "wiki_page_title" => wiki_page_title
        }.compact
        # false means "do nothing": the default version cannot be unset through this tool.
        attrs["default_project_version"] = true if default_project_version == true
        if custom_fields.present?
          attrs["custom_field_values"] = custom_fields.to_h { |field| [ field[:field_id].to_s, field[:value] ] }
        end
        attrs
      end

      # Drop custom field entries without a field_id and symbolize keys.
      # @param custom_fields [Array<Hash>, nil] Raw custom field entries.
      # @return [Array<Hash>] Entries having a field_id.
      def normalize_custom_fields(custom_fields)
        Array(custom_fields).filter_map do |field|
          field = field.to_h.transform_keys(&:to_sym)
          if field[:field_id].nil?
            ai_helper_logger.warn("Skipping a version custom field entry without field_id")
            next
          end
          field
        end
      end

      # Reject a sharing value the current user may not set.
      # @param version [Version] The version.
      # @param sharing [String, nil] The requested sharing.
      # @raise [UserError] if the sharing is not allowed.
      def validate_sharing!(version, sharing)
        return if sharing.nil?
        allowed = version.allowed_sharings(User.current)
        return if allowed.include?(sharing)

        raise UserError, "Sharing '#{sharing}' is not allowed. Allowed values: #{allowed.join(", ")}"
      end

      # Reject custom fields that are not editable for the version by the current user.
      # @param version [Version] The version.
      # @param custom_fields [Array<Hash>] Entries already passed through {#normalize_custom_fields}.
      # @raise [UserError] if a field is not editable.
      def validate_custom_fields!(version, custom_fields)
        return if custom_fields.empty?
        editable = version.editable_custom_field_values(User.current).map(&:custom_field)
        editable_ids = editable.to_set { |cf| cf.id.to_s }
        invalid = custom_fields.map { |field| field[:field_id] }.reject { |id| editable_ids.include?(id.to_s) }
        return if invalid.empty?

        raise UserError, "Custom field not editable for versions: #{invalid.join(", ")}. " \
                         "Editable custom fields: #{editable.map { |cf| "#{cf.id} (#{cf.name})" }.join(", ")}"
      end

      # Convert a version to the result hash returned by the write tools.
      # @param version [Version] The version.
      # @return [Hash] Version attributes and its URL.
      def version_to_hash(version)
        {
          id: version.id,
          project: format_named_record(version.project),
          name: version.name,
          description: version.description,
          status: version.status,
          due_date: version.due_date,
          sharing: version.sharing,
          wiki_page_title: version.wiki_page_title,
          custom_fields: version.visible_custom_field_values(User.current).map do |custom_value|
            { id: custom_value.custom_field.id, name: custom_value.custom_field.name, value: custom_value.value }
          end,
          created_on: version.created_on,
          updated_on: version.updated_on,
          url_for_version: version_url(version, only_path: true)
        }
      end
    end
  end
end
