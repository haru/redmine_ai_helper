# frozen_string_literal: true

require "json"

module RedmineAiHelper
  module Vector
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # This class is responsible for managing the vector database for wiki pages in Redmine.
    class WikiVectorDb < VectorDb
      include ROUTE_HELPERS

      # @!visibility private
      PAYLOAD_INDEX_DECLARATIONS = [
        { field_name: "project_id", field_schema: "integer" },
        { field_name: "created_on", field_schema: "datetime" },
        { field_name: "updated_on", field_schema: "datetime" }
      ].freeze

      # Return the name of the vector index used for this store.
      # @return [String] the canonical index identifier for the wiki embedding index.
      def index_name
        "RedmineWiki"
      end

      # Payload fields that require a Qdrant index so filtered searches work
      # under strict-mode Qdrant Cloud (FR-002 / FR-003).
      # @return [Array<Hash>] field_name / field_schema entries
      def payload_index_declarations
        PAYLOAD_INDEX_DECLARATIONS
      end

      # Checks whether a WikiPage with the specified ID exists.
      # @param object_id [Integer] The ID of the wiki page to check.
      # @return [Boolean] true if the wiki page exists in Redmine's database.
      def data_exists?(object_id)
        WikiPage.exists?(id: object_id)
      end

      # @param object_id [Integer] The ID of the wiki page to check.
      # @return [Boolean] true if the wiki page exists and its project is within the
      #   vector registration scope (ai_helper module enabled and selected, FR-011).
      def data_in_scope?(object_id)
        project = WikiPage.find_by(id: object_id)&.wiki&.project
        return false unless project
        AiHelperSetting.setting.vector_target?(project)
      end

      # A method to generate content and payload for registering a wiki page into the vector database
      # @param wiki [WikiPage] The wiki page to be registered
      # @return [Hash] A hash containing the content and payload for the wiki page
      # @note This method is used to prepare the data for vector database registration
      def data_to_json(wiki)
        payload = {
          wiki_id: wiki.id,
          project_id: wiki.project&.id,
          project_name: wiki.project&.name,
          created_on: wiki.created_on,
          updated_on: wiki.updated_on,
          parent_id: wiki.parent_id,
          parent_title: wiki.parent_title,
          page_url: "#{project_wiki_page_path(wiki.project, wiki.title)}"
        }
        content = "#{wiki.title} #{wiki.content&.text}"

        { content: content, payload: payload }
      end
    end
  end
end
