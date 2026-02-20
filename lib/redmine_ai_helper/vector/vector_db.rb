# frozen_string_literal: true
module RedmineAiHelper
  module Vector
    # This class is responsible for managing the vector database.
    class VectorDb
      attr_accessor :llm_provider

      # Initializes the VectorDb with an optional LLM provider.
      # @param llm_provider [Object] The LLM provider to use for vector operations.
      def initialize(llm_provider: nil)
        @llm_provider = llm_provider || RedmineAiHelper::LlmProvider.get_llm_provider
      end

      # Returns the vector search client.
      # Currently, it uses Qdrant as the vector search client.
      # @return [Object] The vector search client.
      def client
        return nil unless setting.vector_search_enabled
        return @client if @client
        @client = RedmineAiHelper::Vector::Qdrant.new(
          url: setting.vector_search_uri,
          api_key: setting.vector_search_api_key || "dummy",
          index_name: index_name,
          llm_provider: @llm_provider,
        )
        @client
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
      def data_exists?(object_id)
        raise NotImplementedError, "data_exists? method must be implemented in subclass"
      end

      # Generates the schema for the vector database. Must be executed once before registering data.
      def generate_schema
        client.create_default_schema
      end

      # Destroys the schema for the vector database.
      # Data cannot be registered again until generate_schema is executed once more.
      def destroy_schema
        begin
          client.destroy_default_schema
        rescue Faraday::ResourceNotFound
          # do nothing
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
          rescue => e
            begin
              add_data(vector_data: vector_data, data: data, retry_flag: true)
            rescue => e
              unless ENV["RAILS_ENV"] == "test"
                puts ""
                puts "Error: #{index_name} ##{data.id}"
                puts e.message
              end
            end
          end
          print "."
        end
        clean_vector_data
        puts "" unless ENV["RAILS_ENV"] == "test"
      end

      # Registers a single data into the vector database.
      # @param vector_data [AiHelperVectorData] The vector data to be registered.
      # @param data [Object] The data to be registered.
      # @param retry_flag [Boolean] A flag indicating whether to retry the registration.
      # @return [AiHelperVectorData] The registered vector data.
      def add_data(vector_data:, data:, retry_flag: false)
        json = data_to_json(data)
        text = json[:content]
        text = text[0..1500] if retry_flag and text.length
        payload = json[:payload]
        if (vector_data)
          client.add_texts(texts: [text], ids: [vector_data.uuid], payload: payload)
          vector_data.updated_at = Time.now
        else
          uuid = SecureRandom.uuid
          vector_data = AiHelperVectorData.new(object_id: data.id, index: index_name, uuid: uuid)
          client.add_texts(texts: [text], ids: [uuid], payload: payload)
        end

        vector_data.save!
      end

      # Cleans up the vector data by removing any data that no longer exists in Redmine.
      def clean_vector_data
        AiHelperVectorData.where(index: index_name).each do |vector_data|
          if data_exists?(vector_data.object_id)
            next
          end
          client.remove_texts(ids: [vector_data.uuid])
          vector_data.destroy!
          print "." unless ENV["RAILS_ENV"] == "test"
        end
      end

      # search issues from vector db with filter fo payload.
      # @param query [String] The query string to search for.
      # @param filter [Hash] The filter to apply to the search.
      # @param k [Integer] The number of results to return.
      # @return [Array] An array of issues that match the query and filter.
      def ask_with_filter(query:, filter: nil, k: 20)
        return [] unless client
        client.ask_with_filter(
          query: query,
          k: k,
          filter: filter,
        )
      end

      # Searches for similar data in the vector database.
      # @param question [String] The query string to search for.
      # @param k [Integer] The number of results to return.
      # @return [Array] An array of similar data that match the query.
      def similarity_search(question:, k: 10, filter: nil)
        client.similarity_search(query: question, k: k, filter: filter)
      end

      # Converts the data to JSON format.
      # @param data [Object] The data to be converted to JSON.
      # @return [String] The JSON representation of the data.
      def data_to_jsontext(data)
        data.to_json
      end
    end
  end
end
