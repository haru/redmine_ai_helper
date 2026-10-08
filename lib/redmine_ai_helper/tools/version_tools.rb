# frozen_string_literal: true

require "redmine_ai_helper/base_tools"

module RedmineAiHelper
  module Tools
    # VersionTools is a specialized tool for handling Redmine version-related queries.
    class VersionTools < RedmineAiHelper::BaseTools
      define_function :list_versions, description: "List all versions in the project. It returns the version ID, name, description, status, due_date, sharing, wiki_page_title, and created_on." do
        property :project_id, type: "integer", description: "The project ID of the project to return.", required: true
      end
      # List all versions in the project.
      # @param project_id [Integer] The project ID of the project to return.
      # @return [Array<Hash>] An array of hashes containing version information.
      def list_versions(project_id:)
        project = Project.find_by(id: project_id)
        raise("Project not found") if project.nil? or !project.visible?
        raise("Project is not accessible: id = #{project_id}") unless accessible_project?(project)
        versions = project.versions.filter(&:visible?)
        version_list = versions.map do |version|
          {
            id: version.id,
            name: version.name,
            description: version.description,
            status: version.status,
            due_date: version.due_date,
            sharing: version.sharing,
            wiki_page_title: version.wiki_page_title,
            created_on: version.created_on,
            url_for_version: "#{version_url(version, only_path: true)}"
          }
        end

        version_list
      end

      define_function :version_info, description: "Read a version from the database and return it as a JSON object. It returns the version ID, project ID, name, description, status, due_date, sharing, wiki_page_title, created_on, estimated_hours, spent_hours, and issues." do
        property :version_ids, type: "array", description: "The version IDs of the versions to return.", required: true do
          item type: "integer", description: "The version ID of the version to return."
        end
      end
      # Read a version from the database and return it as a JSON object.
      # @param version_ids [Array<Integer>] The version IDs of the versions to return.
      # @return [Array<Hash>] An array of hashes containing version information.
      def version_info(version_ids:)
        versions = []
        # Read the flag once for the whole loop: the accessible_project? default
        # would re-read the settings row per version.
        flag = AiHelperSetting.all_projects_scope?

        version_ids.each do |version_id|
          version = Version.find_by(id: version_id)
          raise("Version not found: version_id: #{version_id}") if version.nil? or !version.visible?
          raise("Project is not accessible: id = #{version.project_id}") unless accessible_project?(version.project, all_projects_scope: flag)
          version_hash = {
            id: version.id,
            project_id: version.project_id,
            name: version.name,
            description: version.description,
            status: version.status,
            due_date: version.due_date,
            sharing: version.sharing,
            wiki_page_title: version.wiki_page_title,
            created_on: version.created_on,
            estimated_hours: version.estimated_hours,
            spent_hours: version.spent_hours,
            url_for_version: "#{version_url(version, only_path: true)}",
            issues: version.fixed_issues.filter(&:visible?).map do |issue|
              {
                id: issue.id,
                subject: issue.subject,
                status: issue.status,
                priority: issue.priority,
                url_for_issue: "#{issue_url(issue, only_path: true)}"
              }
            end
          }
          versions << version_hash
        end
        versions
      end

      define_function :capable_version_properties, description: "Return the values that can be set when creating a version in the project: statuses, sharing values allowed for the current user, and the version custom fields the current user can edit." do
        property :project_id, type: "integer", description: "The project ID of the project in which a version would be created.", required: true
      end
      # Return the values that can be set when creating a version in the project.
      # @param project_id [Integer] The project ID.
      # @return [Hash] statuses, allowed sharings and editable custom fields, or { error: } for a user-caused failure.
      #   Each custom field's possible_values is a list of { value:, label: }; value is what to pass to the write tools.
      def capable_version_properties(project_id:)
        user_errors_as_result do
          raise UserError, "project_id is required" if project_id.nil?
          project = Project.find_by(id: project_id)
          raise UserError, "Project not found. id = #{project_id}" if project.nil?
          raise UserError, "Project is not accessible: id = #{project_id}" unless accessible_project?(project)

          # Built only to ask Redmine for the allowed values; never saved.
          version = project.versions.build
          {
            project_id: project.id,
            statuses: Version::VERSION_STATUSES,
            allowed_sharings: version.allowed_sharings(User.current),
            custom_fields: version.editable_custom_field_values(User.current).map do |custom_value|
              custom_field = custom_value.custom_field
              {
                id: custom_field.id,
                name: custom_field.name,
                field_format: custom_field.field_format,
                is_required: custom_field.is_required,
                multiple: custom_field.multiple?,
                possible_values: possible_value_options(custom_field, version),
                default_value: custom_field.default_value
              }
            end
          }
        end
      end

      private

      # Return the values a custom field accepts, including record IDs for
      # enumeration, user and version formats. Empty for free-input formats.
      # @param custom_field [CustomField] The custom field.
      # @param version [Version] The version the value would be set on.
      # @return [Array<Hash>] { value:, label: } for each possible value.
      def possible_value_options(custom_field, version)
        custom_field.possible_values_options(version).map do |option|
          label, value = Array(option)
          { value: (value || label).to_s, label: label.to_s }
        end
      end
    end
  end
end
