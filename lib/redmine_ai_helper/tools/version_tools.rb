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
        project = Project.find_by_id(project_id)
        raise("Project not found") if project.nil? or !project.visible?
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

        version_ids.each do |version_id|
          version = Version.find_by_id(version_id)
          raise("Version not found: version_id: #{version_id}") if version.nil? or !version.visible?
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
    end
  end
end
