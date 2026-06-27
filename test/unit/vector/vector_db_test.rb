require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/vector/vector_db"

class RedmineAiHelper::Vector::VectorDbTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields
  context "VectorDb" do
    setup do
      @qdrant_stub = QdrantStub.new
      RedmineAiHelper::Vector::Qdrant.stubs(:new).returns(@qdrant_stub)
      @vector_db = RedmineAiHelper::Vector::VectorDb.new
      @issue_vector_db = RedmineAiHelper::Vector::IssueVectorDb.new
      @setting = AiHelperSetting.find_or_create
      @setting.vector_search_enabled = true
      @setting.vector_search_uri = "http://example.com"
      @setting.save!
      AiHelperVectorData.destroy_all
    end

    teardown do
      @setting.vector_search_enabled = false
      @setting.save!
    end

    should "return client" do
      client = @issue_vector_db.client

      assert client
    end

    should "raise error with index_name" do
      assert_raises NotImplementedError do
        @vector_db.index_name
      end
    end

    should "raise error with data_exists?" do
      assert_raises NotImplementedError do
        @vector_db.data_exists?(1)
      end
    end

    should "raise NotImplementedError with in_scope_object_ids" do
      assert_raises NotImplementedError do
        @vector_db.in_scope_object_ids
      end
    end

    should "not error with generate_schema" do
      mock_provider = mock("llm_provider")
      mock_provider.stubs(:embed).returns([ 0.1 ] * 3072)
      issue_vector_db = RedmineAiHelper::Vector::IssueVectorDb.new(llm_provider: mock_provider)

      assert issue_vector_db.generate_schema
    end

    should "not error with destory_schema" do
      assert @issue_vector_db.destroy_schema
    end

      context "add_datas" do
        should "add vector data" do
          issue = Issue.first
          issue.description = "#{"a" * 2000}"
          issue.save!
          issues = Issue.all
          @issue_vector_db.add_datas(datas: issues)

          assert_equal issues.length, AiHelperVectorData.count
          issue.subject = "aaaa"
          issue.save!
          issues = Issue.all
          @issue_vector_db.add_datas(datas: issues)

          assert_equal issues.length, AiHelperVectorData.count
        end

        should "skip data that is already up-to-date" do
          issue = Issue.first
          issue.description = "#{"a" * 2000}"
          issue.save!

          @issue_vector_db.add_datas(datas: [ issue ])

          client_mock = mock("client")
          client_mock.expects(:add_texts).never
          @issue_vector_db.stubs(:client).returns(client_mock)

          @issue_vector_db.add_datas(datas: [ issue ])
        end

        should "not call clean_vector_data internally" do
          issue = Issue.first
          issue.description = "#{"a" * 2000}"
          issue.save!

          @issue_vector_db.expects(:clean_vector_data).never
          @issue_vector_db.add_datas(datas: [ issue ])
        end
      end

      context "clean_vector_data" do
        should "deletes data whose source is no longer in scope" do
          issue = Issue.first
          issue.description = "#{"a" * 2000}"
          issue.save!
          @issue_vector_db.add_datas(datas: [ issue ])

          issue.destroy!
          result = @issue_vector_db.clean_vector_data

          assert_equal({ deleted: 1, failed: 0 }, result)
        end

        should "return hash with deleted and failed counts" do
          result = @issue_vector_db.clean_vector_data

          assert_instance_of Hash, result
          assert result.key?(:deleted)
          assert result.key?(:failed)
          assert_kind_of Integer, result[:deleted]
          assert_kind_of Integer, result[:failed]
        end

        should "log warn and increment failed counter on individual Qdrant failure" do
          issue = Issue.first
          @issue_vector_db.add_datas(datas: [ issue ])

          @qdrant_stub.instance_variable_set(:@next_remove_fails, true)

          logger = RedmineAiHelper::CustomLogger.instance
          logger.expects(:warn).at_least_once.with(regexp_matches(/failed to remove vector_data/))

          @issue_vector_db.stubs(:in_scope_object_ids).returns(Set.new)
          result = @issue_vector_db.clean_vector_data

          assert_equal 1, result[:failed]
          assert_equal 0, result[:deleted]
        end
      end

    context "VectorDb uses vector model profile provider" do
      setup do
        @vector_profile = AiHelperModelProfile.create!(
          name: "Vector Profile",
          llm_model: "text-embedding-3-large",
          access_key: "vec_key",
          temperature: 0.0,
          base_uri: "https://api.openai.com",
          max_tokens: 0,
          llm_type: "OpenAI"
        )
      end

      teardown do
        @setting.update_columns(use_vector_model_profile: false, vector_model_profile_id: nil)
        @vector_profile.destroy if @vector_profile.persisted?
      end

      should "use vector profile provider when configured" do
        @setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: @vector_profile.id)
        vector_db = RedmineAiHelper::Vector::IssueVectorDb.new

        assert_equal @vector_profile.llm_model, vector_db.llm_provider.model_name
      end

      should "use default provider when use_vector_model_profile is false" do
        @setting.update_columns(use_vector_model_profile: false, vector_model_profile_id: nil)
        default_provider = RedmineAiHelper::LlmProvider.get_llm_provider
        vector_db = RedmineAiHelper::Vector::IssueVectorDb.new

        assert_equal default_provider.model_name, vector_db.llm_provider.model_name
      end
    end

    context "ask_with_filter" do
      should "return array" do
        res = @issue_vector_db.ask_with_filter(query: "test")

        assert_equal [ "test" ], res
      end
    end

    context "similarity_search" do
      should "delegate to client similarity_search without filter" do
        res = @issue_vector_db.similarity_search(question: "test query", k: 5)

        assert_equal [ { "payload" => { "issue_id" => 1 }, "score" => 0.9 } ], res
      end

      should "pass filter parameter to client similarity_search" do
        filter = {
          must: [
            { key: "project_id", match: { value: 1 } }
          ]
        }
        res = @issue_vector_db.similarity_search(question: "test query", k: 5, filter: filter)

        assert_equal [ { "payload" => { "issue_id" => 1 }, "score" => 0.9 } ], res
        assert_equal filter, @qdrant_stub.last_filter
      end

      should "default filter to nil" do
        @issue_vector_db.similarity_search(question: "test query", k: 5)

        assert_nil @qdrant_stub.last_filter
      end
    end

    context "payload_index_declarations" do
      should "raise NotImplementedError in the base class" do
        assert_raises NotImplementedError do
          @vector_db.payload_index_declarations
        end
      end
    end

    context "ensure_payload_indexes" do
      setup do
        @mock_client = mock("qdrant_client")
        @subclass = Class.new(RedmineAiHelper::Vector::VectorDb) do
          def index_name
            "TestCollection"
          end

          def data_exists?(_)
            false
          end

          def payload_index_declarations
            [
              { field_name: "project_id", field_schema: "integer" },
              { field_name: "tracker_id", field_schema: "integer" },
              { field_name: "created_on", field_schema: "datetime" }
            ]
          end
        end
        @instance = @subclass.new
        @instance.stubs(:client).returns(@mock_client)
      end

      should "create absent indexes, skip matching ones, and report mismatches" do
        @mock_client.expects(:fetch_payload_schema).once.returns(
          {
            "project_id" => "integer",
            "tracker_id" => "keyword"
          }
        )
        @mock_client.expects(:create_payload_index).with(
          field_name: "created_on", field_schema: "datetime"
        ).once.returns({ "status" => "ok" })

        result = @instance.ensure_payload_indexes

        assert_equal :matching, result[:results]["project_id"]
        assert_equal :mismatch, result[:results]["tracker_id"]
        assert_equal :created, result[:results]["created_on"]
      end

      should "log each per-field result via ai_helper_logger.info" do
        @mock_client.stubs(:fetch_payload_schema).returns({})
        @mock_client.stubs(:create_payload_index).returns({ "status" => "ok" })
        logger = RedmineAiHelper::CustomLogger.instance
        logger.expects(:info).at_least(3)

        @instance.ensure_payload_indexes
      end

      should "re-raise Qdrant API exceptions without fallback" do
        @mock_client.expects(:fetch_payload_schema).returns({})
        @mock_client.expects(:create_payload_index).raises(Faraday::ServerError.new("boom"))

        assert_raises(Faraday::ServerError) do
          @instance.ensure_payload_indexes
        end
      end

      should "return :matching for every field on a repeat run (idempotency, FR-004)" do
        @mock_client.expects(:fetch_payload_schema).once.returns(
          {
            "project_id" => "integer",
            "tracker_id" => "integer",
            "created_on" => "datetime"
          }
        )
        @mock_client.expects(:create_payload_index).never

        result = @instance.ensure_payload_indexes

        assert_equal({ "project_id" => :matching, "tracker_id" => :matching, "created_on" => :matching }, result[:results])
        assert_equal({ "project_id" => "integer", "tracker_id" => "integer", "created_on" => "datetime" }, result[:schema])
      end
    end

    context "generate_schema call order" do
      setup do
        @mock_provider = mock("llm_provider")
        @mock_provider.stubs(:embed).returns([ 0.1 ] * 3072)
        @issue_db_for_order = RedmineAiHelper::Vector::IssueVectorDb.new(llm_provider: @mock_provider)
      end

      should "call ensure_payload_indexes after create_default_schema" do
        seq = sequence("generate_schema_order")
        client = mock("client")
        client.expects(:create_default_schema).with(vector_size: 3072).in_sequence(seq).returns(true)
        @issue_db_for_order.stubs(:client).returns(client)
        @issue_db_for_order.expects(:ensure_payload_indexes).in_sequence(seq).returns({})

        @issue_db_for_order.generate_schema
      end
    end
  end

  class QdrantStub
    attr_reader :last_filter

    def initialize
      @next_remove_fails = false
    end

    def create_default_schema(vector_size: 1536) # rubocop:disable Lint/UnusedMethodArgument
      ""
    end

    def destroy_default_schema
      true
    end

    def add_texts(texts:, ids:, payload:) # rubocop:disable Lint/UnusedMethodArgument
      if texts[0].length > 1500
        raise "Error"
      end
    end

    def remove_texts(ids:) # rubocop:disable Lint/UnusedMethodArgument
      if @next_remove_fails
        @next_remove_fails = false
        raise Faraday::ServerError.new("Qdrant remove failed")
      end
      true
    end

    def ask_with_filter(query:, k: 20, filter: nil) # rubocop:disable Lint/UnusedMethodArgument
      [ "test" ]
    end

    def similarity_search(query:, k: 4, filter: nil) # rubocop:disable Lint/UnusedMethodArgument
      @last_filter = filter
      [ { "payload" => { "issue_id" => 1 }, "score" => 0.9 } ]
    end

    def fetch_payload_schema
      {}
    end

    def create_payload_index(field_name:, field_schema:) # rubocop:disable Lint/UnusedMethodArgument
      { "status" => "ok" }
    end
  end
end
