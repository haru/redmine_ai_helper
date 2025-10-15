# frozen_string_literal: true
require "json"

module RedmineAiHelper
  module Vector
    # @!visibility private
    ROUTE_HELPERS = Rails.application.routes.url_helpers unless const_defined?(:ROUTE_HELPERS)
    # This class is responsible for managing the vector database for issues in Redmine.
    class WikiVectorDb < VectorDb
      include ROUTE_HELPERS

      # Return the name of the vector index used for this store.
      # @return [String] the canonical index identifier for the wiki embedding index.
      def index_name
        "RedmineWiki"
      end

      # Checks whether an Issue with the specified ID exists.
      # @param object_id [Integer] The ID of the issue to check.
      def data_exists?(object_id)
        WikiPage.exists?(id: object_id)
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
          page_url: "#{project_wiki_page_path(wiki.project, wiki.title)}",
        }
        content = "#{wiki.title} #{wiki.content.text}"

        return { content: content, payload: payload }
      end
    end
  end
end
