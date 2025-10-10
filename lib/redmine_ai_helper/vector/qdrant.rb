# frozen_string_literal: true
require "langchain"

module RedmineAiHelper
  # Vector search functionality
  module Vector
    # Langchainrb's Qdrant does not support payload filtering,
    # so it is implemented independently by inheritance
    class Qdrant < Langchain::Vectorsearch::Qdrant

      # search data from vector db with filter for payload.
      # @param query [String] The query string to search for.
      # @param filter [Hash] The filter to apply to the search.
      # @param k [Integer] The number of results to return.
      # @return [Array] An array of issues that match the query and filter.
      def ask_with_filter(query:, k: 20, filter: nil)
        return [] unless client

        embedding = llm.embed(text: query).embedding

        response = client.points.search(
          collection_name: index_name,
          limit: k,
          vector: embedding,
          with_payload: true,
          with_vector: true,
          filter: filter,
        )
        results = response.dig("result")
        return [] unless results.is_a?(Array)

        results.map do |result|
          result.dig("payload")
        end
      end
    end
  end
end
