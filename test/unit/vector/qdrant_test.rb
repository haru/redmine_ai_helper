require File.expand_path("../../../test_helper", __FILE__)

class RedmineAiHelper::Vector::QdrantTest < ActiveSupport::TestCase
  context "Qdrant" do
    setup do
      @mock_client = mock("client")
      @mock_points = mock("points")
      @mock_collections = mock("collections")
      @mock_llm_provider = mock("llm_provider")
      @mock_llm_provider.stubs(:embed).returns([0.1, 0.2, 0.3])

      @qdrant = RedmineAiHelper::Vector::Qdrant.new(
        url: "http://localhost:6333",
        api_key: "test_key",
        index_name: "test_collection",
        llm_provider: @mock_llm_provider,
      )
      # Inject mock client
      @qdrant.instance_variable_set(:@client, @mock_client)
    end

    context "initialize" do
      should "store url, api_key, index_name and llm_provider" do
        qdrant = RedmineAiHelper::Vector::Qdrant.new(
          url: "http://example.com",
          api_key: "my_key",
          index_name: "my_index",
          llm_provider: @mock_llm_provider,
        )
        assert_equal "http://example.com", qdrant.url
        assert_equal "my_key", qdrant.api_key
        assert_equal "my_index", qdrant.index_name
        assert_equal @mock_llm_provider, qdrant.llm_provider
      end
    end

    context "client" do
      should "create a Qdrant::Client with correct params" do
        qdrant = RedmineAiHelper::Vector::Qdrant.new(
          url: "http://localhost:6333",
          api_key: "test_key",
          index_name: "test_collection",
          llm_provider: @mock_llm_provider,
        )
        mock_qdrant_client = mock("Qdrant::Client")
        ::Qdrant::Client.expects(:new).with(url: "http://localhost:6333", api_key: "test_key").returns(mock_qdrant_client)
        assert_equal mock_qdrant_client, qdrant.client
      end
    end

    context "embed" do
      should "delegate to llm_provider.embed" do
        @mock_llm_provider.expects(:embed).with("test text").returns([0.4, 0.5, 0.6])
        result = @qdrant.embed("test text")
        assert_equal [0.4, 0.5, 0.6], result
      end
    end

    context "add_texts" do
      should "embed texts and upsert to qdrant" do
        @mock_llm_provider.stubs(:embed).with("text1").returns([0.1, 0.2])
        @mock_llm_provider.stubs(:embed).with("text2").returns([0.3, 0.4])
        @mock_client.stubs(:points).returns(@mock_points)

        @mock_points.expects(:upsert).with(
          collection_name: "test_collection",
          points: [
            { id: "id1", vector: [0.1, 0.2], payload: { key: "val" } },
            { id: "id2", vector: [0.3, 0.4], payload: { key: "val" } },
          ],
        )

        @qdrant.add_texts(texts: ["text1", "text2"], ids: ["id1", "id2"], payload: { key: "val" })
      end

      should "use empty hash as default payload" do
        @mock_llm_provider.stubs(:embed).with("text1").returns([0.1, 0.2])
        @mock_client.stubs(:points).returns(@mock_points)

        @mock_points.expects(:upsert).with(
          collection_name: "test_collection",
          points: [
            { id: "id1", vector: [0.1, 0.2], payload: {} },
          ],
        )

        @qdrant.add_texts(texts: ["text1"], ids: ["id1"])
      end
    end

    context "remove_texts" do
      should "delete points by IDs" do
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:delete).with(
          collection_name: "test_collection",
          points: ["uuid1", "uuid2"],
        )

        @qdrant.remove_texts(ids: ["uuid1", "uuid2"])
      end
    end

    context "ask_with_filter" do
      should "return empty array if client is nil" do
        @qdrant.instance_variable_set(:@client, nil)
        # Also need to stub Qdrant::Client.new to return nil
        ::Qdrant::Client.stubs(:new).returns(nil)
        results = @qdrant.ask_with_filter(query: "test", k: 5, filter: nil)
        assert_equal [], results
      end

      should "call client.points.search with correct parameters and return payloads" do
        mock_response = {
          "result" => [
            { "payload" => { "id" => 1, "title" => "Issue 1" } },
            { "payload" => { "id" => 2, "title" => "Issue 2" } },
          ],
        }
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:search).with(
          collection_name: "test_collection",
          limit: 2,
          vector: [0.1, 0.2, 0.3],
          with_payload: true,
          with_vector: true,
          filter: { foo: "bar" },
        ).returns(mock_response)

        results = @qdrant.ask_with_filter(query: "test", k: 2, filter: { foo: "bar" })
        assert_equal [{ "id" => 1, "title" => "Issue 1" }, { "id" => 2, "title" => "Issue 2" }], results
      end

      should "return empty array if result is nil" do
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.stubs(:search).returns({ "result" => nil })
        results = @qdrant.ask_with_filter(query: "test", k: 1, filter: nil)
        assert_equal [], results
      end

      should "return empty array if result is empty" do
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.stubs(:search).returns({ "result" => [] })
        results = @qdrant.ask_with_filter(query: "test", k: 1, filter: nil)
        assert_equal [], results
      end
    end

    context "similarity_search" do
      should "return payload and score for each result" do
        mock_response = {
          "result" => [
            { "payload" => { "issue_id" => 1 }, "score" => 0.95 },
            { "payload" => { "issue_id" => 2 }, "score" => 0.85 },
          ],
        }
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:search).with(
          collection_name: "test_collection",
          limit: 4,
          vector: [0.1, 0.2, 0.3],
          with_payload: true,
          with_vector: false,
          filter: nil,
        ).returns(mock_response)

        results = @qdrant.similarity_search(query: "test query")
        assert_equal 2, results.length
        assert_equal({ "payload" => { "issue_id" => 1 }, "score" => 0.95 }, results[0])
        assert_equal({ "payload" => { "issue_id" => 2 }, "score" => 0.85 }, results[1])
      end

      should "return empty array when no results" do
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.stubs(:search).returns({ "result" => [] })
        results = @qdrant.similarity_search(query: "test query")
        assert_equal [], results
      end

      should "return empty array when result is nil" do
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.stubs(:search).returns({ "result" => nil })
        results = @qdrant.similarity_search(query: "test query")
        assert_equal [], results
      end

      should "accept custom k parameter" do
        mock_response = {
          "result" => [
            { "payload" => { "issue_id" => 1 }, "score" => 0.9 },
          ],
        }
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:search).with(
          collection_name: "test_collection",
          limit: 10,
          vector: [0.1, 0.2, 0.3],
          with_payload: true,
          with_vector: false,
          filter: nil,
        ).returns(mock_response)

        results = @qdrant.similarity_search(query: "test query", k: 10)
        assert_equal 1, results.length
      end

      should "pass filter parameter to Qdrant API" do
        filter = {
          must: [
            { key: "project_id", match: { value: 1 } }
          ]
        }
        mock_response = {
          "result" => [
            { "payload" => { "issue_id" => 1, "project_id" => 1 }, "score" => 0.95 },
          ],
        }
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:search).with(
          collection_name: "test_collection",
          limit: 4,
          vector: [0.1, 0.2, 0.3],
          with_payload: true,
          with_vector: false,
          filter: filter,
        ).returns(mock_response)

        results = @qdrant.similarity_search(query: "test query", filter: filter)
        assert_equal 1, results.length
        assert_equal({ "payload" => { "issue_id" => 1, "project_id" => 1 }, "score" => 0.95 }, results[0])
      end

      should "pass nil filter when not specified" do
        mock_response = {
          "result" => [
            { "payload" => { "issue_id" => 1 }, "score" => 0.9 },
          ],
        }
        @mock_client.stubs(:points).returns(@mock_points)
        @mock_points.expects(:search).with(
          collection_name: "test_collection",
          limit: 4,
          vector: [0.1, 0.2, 0.3],
          with_payload: true,
          with_vector: false,
          filter: nil,
        ).returns(mock_response)

        results = @qdrant.similarity_search(query: "test query")
        assert_equal 1, results.length
      end
    end

    context "create_default_schema" do
      should "create collection with correct params" do
        @mock_client.stubs(:collections).returns(@mock_collections)
        @mock_collections.expects(:create).with(
          collection_name: "test_collection",
          vectors: { size: 1536, distance: "Cosine" },
        )
        @qdrant.create_default_schema
      end

      should "accept custom vector_size" do
        @mock_client.stubs(:collections).returns(@mock_collections)
        @mock_collections.expects(:create).with(
          collection_name: "test_collection",
          vectors: { size: 3072, distance: "Cosine" },
        )
        @qdrant.create_default_schema(vector_size: 3072)
      end
    end

    context "destroy_default_schema" do
      should "delete the collection" do
        @mock_client.stubs(:collections).returns(@mock_collections)
        @mock_collections.expects(:delete).with(collection_name: "test_collection")
        @qdrant.destroy_default_schema
      end
    end
  end
end
