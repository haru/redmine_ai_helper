# frozen_string_literal: true

module RedmineAiHelper
  module Vector
    # This class is responsible for managing the vector database.
    class VectorDb
      include RedmineAiHelper::Logger

      attr_accessor :llm_provider

      # Initializes the VectorDb with an optional LLM provider.
      # @param llm_provider [Object] The LLM provider to use for vector operations.
      def initialize(llm_provider: nil)
        @llm_provider = llm_provider || RedmineAiHelper::LlmProvider.get_vector_llm_provider
      end

      # Returns the vector search client.
      # Currently, it uses Qdrant as the vector search client.
      # @return [Object, nil] The vector search client, or nil if vector search is disabled.
      def client
        return nil unless setting.vector_search_enabled
        @client ||= RedmineAiHelper::Vector::Qdrant.new(
          url: setting.vector_search_uri,
          api_key: setting.vector_search_api_key || "dummy",
          index_name: index_name,
          llm_provider: @llm_provider
        )
      end

      # Returns the setting for the vector database.
      def setting
        @setting ||= AiHelperSetting.find_or_create
      end

      # Returns the index name for the vector database.
      def index_name
        raise NotImplementedError, "index_name method must be implemented in subclass"
      end

      # This method checks whether the object stored in the vector DB exists in Redmine's database.
      # It is necessary to implement this method because objects stored in the vector DB may have been deleted in Redmine.
      # @param object_id [Integer] The ID of the object to check.
      # @return [Boolean] true if the object exists in Redmine's database.
      def data_exists?(object_id)
        raise NotImplementedError, "data_exists? method must be implemented in subclass"
      end

      # Whether the source object identified by object_id still belongs to a project
      # whose ai_helper module is enabled. Subclasses MUST implement this.
      # @param object_id [Integer] Issue.id or WikiPage.id
      # @return [Boolean] true if the source exists AND its project has ai_helper module enabled
      def data_in_scope?(object_id)
        raise NotImplementedError, "data_in_scope? method must be implemented in subclass"
      end

      # Generates the schema for the vector database. Must be executed once before registering data.
      def generate_schema
        return unless client
        vector_size = detect_vector_size
        client.create_default_schema(vector_size: vector_size)
        ensure_payload_indexes
      end

      # Declarations of payload indexes required by this collection.
      # Subclasses must override to return an array of
      # { field_name: String, field_schema: String } hashes.
      # @return [Array<Hash>] declarations
      def payload_index_declarations
        raise NotImplementedError, "payload_index_declarations method must be implemented in subclass"
      end

      # Ensure the payload indexes declared by this collection exist on Qdrant.
      # Fetches the current payload schema once, then for each declaration either
      # creates a missing index, skips a matching one, or reports a type mismatch.
      # @return [Hash{ results: Hash<String, Symbol>, schema: Hash }]
      #   results: field_name => :created | :matching | :mismatch
      #   schema:  the fetched payload schema
      def ensure_payload_indexes
        return unless client
        existing = client.fetch_payload_schema
        results = payload_index_declarations.each_with_object({}) do |declaration, result|
          field_name = declaration[:field_name]
          expected_schema = declaration[:field_schema]
          existing_schema = existing[field_name]

          state =
            if existing_schema.nil?
              client.create_payload_index(field_name: field_name, field_schema: expected_schema)
              :created
            elsif existing_schema == expected_schema
              :matching
            else
              :mismatch
            end

          log_payload_index_result(field_name, expected_schema, existing_schema, state)
          result[field_name] = state
        end
        { results: results, schema: existing }
      end

      # Detects the vector dimension by embedding a short test text.
      # Raises an exception if the API call fails (no fallback).
      # @return [Integer] the vector dimension
      def detect_vector_size
        vectors = @llm_provider.embed("test")
        vectors.length
      end

      # Destroys the schema for the vector database.
      # Data cannot be registered again until generate_schema is executed once more.
      def destroy_schema
        begin
          client.destroy_default_schema
        rescue Faraday::ResourceNotFound
          ai_helper_logger.info("[#{index_name}] destroy_schema: collection not found (already destroyed)")
        end
        AiHelperVectorData.where(index: index_name).destroy_all
      end

      # Registers datas into the vector database.
      # @param datas [Array] The array of data to be registered.
      def add_datas(datas:)
        return if datas.empty?
        datas.each do |data|
          vector_data = AiHelperVectorData.find_by(object_id: data.id, index: index_name)
          next if vector_data and data.updated_on < vector_data.updated_at
          begin
            add_data(vector_data: vector_data, data: data)
          rescue Faraday::Error
            begin
              add_data(vector_data: vector_data, data: data, retry_flag: true)
            rescue Faraday::Error => e
              ai_helper_logger.error("[#{index_name}] add_data failed ##{data.id}: #{e.class}: #{e.message}")
            end
          end
        end
      end

      # Remove vector data whose source object is no longer in scope (deleted source
      # or project with ai_helper module disabled). Returns aggregated counts.
      # @return [Hash{Symbol => Integer}] { deleted: Integer, failed: Integer }
      def clean_vector_data
        deleted = 0
        failed = 0
        AiHelperVectorData.where(index: index_name).find_each do |vector_data|
          next if data_in_scope?(vector_data.object_id)
          begin
            client.remove_texts(ids: [ vector_data.uuid ])
            vector_data.destroy!
            deleted += 1
          rescue Faraday::Error => e
            failed += 1
            ai_helper_logger.warn(
              "[#{index_name}] failed to remove vector_data id=#{vector_data.id} uuid=#{vector_data.uuid}: #{e.class}: #{e.message}"
            )
          end
        end
        { deleted: deleted, failed: failed }
      end

      # Registers a single data into the vector database.
      # @param vector_data [AiHelperVectorData] The vector data to be registered.
      # @param data [Object] The data to be registered.
      # @param retry_flag [Boolean] A flag indicating whether to retry the registration.
      # @return [AiHelperVectorData] The registered vector data.
      def add_data(vector_data:, data:, retry_flag: false)
        json = data_to_json(data)
        text = json[:content]
        text = text[0..1500] if retry_flag && text.length > 1500
        payload = json[:payload]
        if vector_data
          client.add_texts(texts: [ text ], ids: [ vector_data.uuid ], payload: payload)
          vector_data.updated_at = Time.zone.now
        else
          uuid = SecureRandom.uuid
          vector_data = AiHelperVectorData.new(object_id: data.id, index: index_name, uuid: uuid)
          client.add_texts(texts: [ text ], ids: [ uuid ], payload: payload)
        end

        vector_data.save!
      end

      # Search data from vector database with filter for payload.
      # @param query [String] The query string to search for.
      # @param filter [Hash] The filter to apply to the search.
      # @param k [Integer] The number of results to return.
      # @return [Array] An array of results that match the query and filter.
      def ask_with_filter(query:, filter: nil, k: 20)
        return [] unless client
        client.ask_with_filter(
          query: query,
          k: k,
          filter: filter
        )
      end

      # Searches for similar data in the vector database.
      # @param question [String] The query string to search for.
      # @param k [Integer] The number of results to return.
      # @param filter [Hash, nil] The filter to apply to the search.
      # @return [Array] An array of similar data that match the query.
      def similarity_search(question:, k: 10, filter: nil)
        return [] unless client
        client.similarity_search(query: question, k: k, filter: filter)
      end

      # Converts the data to JSON format.
      # @param data [Object] The data to be converted to JSON.
      # @return [String] The JSON representation of the data.
      def data_to_jsontext(data)
        data.to_json
      end

      private

      # Emit a single line describing the per-field payload index decision.
      def log_payload_index_result(field_name, expected_schema, existing_schema, state)
        message = case state
        when :created
                    "[#{index_name}] #{field_name} #{expected_schema} created"
        when :matching
                    "[#{index_name}] #{field_name} #{expected_schema} matching"
        when :mismatch
                    "[#{index_name}] #{field_name} MISMATCH (existing: #{existing_schema}, expected: #{expected_schema})"
        end
        ai_helper_logger.info(message)
      end
    end
  end
end
