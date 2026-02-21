# frozen_string_literal: true

require "qdrant"

module RedmineAiHelper
  # Vector search utilities for issue and wiki content similarity.
  module Vector
    # Qdrant vector search client using qdrant-ruby gem directly.
    class Qdrant
      include RedmineAiHelper::Logger

      attr_reader :url, :api_key, :index_name, :llm_provider

      # @param url [String] The Qdrant server URL.
      # @param api_key [String] The Qdrant API key.
      # @param index_name [String] The collection name.
      # @param llm_provider [Object] The LLM provider for embedding (must respond to #embed).
      def initialize(url:, api_key:, index_name:, llm_provider:)
        @url = url
        @api_key = api_key
        @index_name = index_name
        @llm_provider = llm_provider
      end

      # Returns the qdrant-ruby client, lazily initialized.
      # @return [::Qdrant::Client] The Qdrant client instance.
      def client
        # Pass the plugin's custom logger so Faraday HTTP logs are routed to
        # log/ai_helper.log instead of being printed to STDOUT.
        @client ||= ::Qdrant::Client.new(url: @url, api_key: @api_key, logger: RedmineAiHelper::CustomLogger.instance)
      end

      # Generate embedding via LLM provider (uses RubyLLM).
      # @param text [String] The text to embed.
      # @return [Array<Float>] The embedding vector.
      def embed(text)
        @llm_provider.embed(text)
      end

      # Upsert texts with embeddings into the Qdrant collection.
      # @param texts [Array<String>] The texts to embed and store.
      # @param ids [Array<String>] The point IDs.
      # @param payload [Hash, nil] Optional payload to attach to each point.
      def add_texts(texts:, ids:, payload: nil)
        vectors = texts.map { |text| embed(text) }
        points = ids.zip(vectors).map do |id, vector|
          { id: id, vector: vector, payload: payload || {} }
        end
        response = client.points.upsert(collection_name: @index_name, points: points)
        unless response.is_a?(Hash) && response["status"] == "ok"
          raise "Qdrant upsert failed: #{response.inspect}"
        end
        response
      end

      # Delete points by IDs from the Qdrant collection.
      # @param ids [Array<String>] The point IDs to delete.
      def remove_texts(ids:)
        client.points.delete(collection_name: @index_name, points: ids)
      end

      # Search data from vector db with filter for payload.
      # @param query [String] The query string to search for.
      # @param k [Integer] The number of results to return.
      # @param filter [Hash, nil] The filter to apply to the search.
      # @return [Array<Hash>] An array of payload hashes that match the query and filter.
      def ask_with_filter(query:, k: 20, filter: nil)
        return [] unless client

        embedding = embed(query)

        response = client.points.search(
          collection_name: @index_name,
          limit: k,
          vector: embedding,
          with_payload: true,
          with_vector: true,
          filter: filter,
        )
        results = response.dig("result")
        return [] unless results.is_a?(Array)

        results.map { |result| result.dig("payload") }
      end

      # Similarity search returning payload and score for each result.
      # Unlike ask_with_filter (which returns only payloads), this method
      # preserves similarity scores for ranking purposes.
      # @param query [String] The query string.
      # @param k [Integer] The number of results to return.
      # @return [Array<Hash>] Each hash contains "payload" and "score" keys.
      def similarity_search(query:, k: 4, filter: nil)
        return [] unless client

        embedding = embed(query)

        response = client.points.search(
          collection_name: @index_name,
          limit: k,
          vector: embedding,
          with_payload: true,
          with_vector: false,
          filter: filter,
        )
        results = response.dig("result")
        return [] unless results.is_a?(Array)

        results.map do |result|
          {
            "payload" => result.dig("payload"),
            "score" => result.dig("score"),
          }
        end
      end

      # Create the default collection schema in Qdrant.
      # @param vector_size [Integer] The vector dimension size (default 1536 for OpenAI ada-002).
      def create_default_schema(vector_size: 1536)
        client.collections.create(
          collection_name: @index_name,
          vectors: { size: vector_size, distance: "Cosine" },
        )
      end

      # Destroy the collection from Qdrant.
      def destroy_default_schema
        client.collections.delete(collection_name: @index_name)
      end
    end
  end
end
