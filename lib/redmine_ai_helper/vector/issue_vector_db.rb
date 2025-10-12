# frozen_string_literal: true
require "json"

module RedmineAiHelper
  module Vector
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # This class is responsible for managing the vector database for issues in Redmine.
    class IssueVectorDb < VectorDb
      include ROUTE_HELPERS

      # Return the name of the vector index used for this store.
      # @return [String] the canonical index identifier for the issue embedding index.
      def index_name
        "RedmineIssue"
      end

      # Checks whether an Issue with the specified ID exists.
      # @param object_id [Integer] The ID of the issue to check.
      def data_exists?(object_id)
        Issue.exists?(id: object_id)
      end

      # A method to generate content and payload for registering an issue into the vector database
      # @param issue [Issue] The issue to be registered.
      # @return [Hash] A hash containing the content and payload for the issue.
      # @note This method is used to prepare the data for vector database registration.
      def data_to_json(issue)
        payload = {
          issue_id: issue.id,
          project_id: issue.project.id,
          project_name: issue.project.name,
          author_id: issue.author&.id,
          author_name: issue.author&.name,
          subject: issue.subject,
          description: issue.description,
          status_id: issue.status.id,
          status: issue.status.name,
          priority_id: issue.priority.id,
          priority: issue.priority.name,
          assigned_to_id: issue.assigned_to&.id,
          assigned_to_name: issue.assigned_to&.name,
          created_on: issue.created_on,
          updated_on: issue.updated_on,
          due_date: issue.due_date,
          tracker_id: issue.tracker.id,
          tracker_name: issue.tracker.name,
          version_id: issue.fixed_version&.id,
          version_name: issue.fixed_version&.name,
          category_name: issue.category&.name,
          issue_url: issue_url(issue, only_path: true),
        }
        content = "#{issue.subject} #{issue.description}"
        content += " " + issue.journals.map { |journal| journal.notes.to_s }.join(" ")

        return { content: content, payload: payload }
      end
    end
  end
end
