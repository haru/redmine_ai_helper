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

    should "not error with generate_schema" do
      mock_provider = mock("llm_provider")
      mock_provider.stubs(:embed).returns([0.1] * 3072)
      issue_vector_db = RedmineAiHelper::Vector::IssueVectorDb.new(llm_provider: mock_provider)
      assert issue_vector_db.generate_schema
    end

    should "not error with destory_schema" do
      assert @issue_vector_db.destroy_schema
    end

    context "add_datas" do
      setup do
      end

      should "add vector data" do
        issue = Issue.first
        issue.description = "#{"a" * 2000}"
        issue.save!
        issues = Issue.all
        @issue_vector_db.add_datas(datas: issues)
        assert issues.length, AiHelperVectorData.all.length
        issue.subject = "aaaa"
        issue.save!
        issues = Issue.all
        @issue_vector_db.add_datas(datas: issues)
        assert issues.length, AiHelperVectorData.all.length
      end

      context "clean_vector_data" do
        should "deletes data" do
          issues = Issue.all
          @issue_vector_db.add_datas(datas: issues)
          issues.first.destroy!
          issues = Issue.all
          @issue_vector_db.clean_vector_data
          assert issues.length, AiHelperVectorData.all.length
          @issue_vector_db.clean_vector_data
        end
      end
    end

    context "ask_with_filter" do
      should "return array" do
        res = @issue_vector_db.ask_with_filter(query: "test")
        assert_equal res, ["test"]
      end
    end

    context "similarity_search" do
      should "delegate to client similarity_search without filter" do
        res = @issue_vector_db.similarity_search(question: "test query", k: 5)
        assert_equal [{ "payload" => { "issue_id" => 1 }, "score" => 0.9 }], res
      end

      should "pass filter parameter to client similarity_search" do
        filter = {
          must: [
            { key: "project_id", match: { value: 1 } }
          ]
        }
        res = @issue_vector_db.similarity_search(question: "test query", k: 5, filter: filter)
        assert_equal [{ "payload" => { "issue_id" => 1 }, "score" => 0.9 }], res
        assert_equal filter, @qdrant_stub.last_filter
      end

      should "default filter to nil" do
        @issue_vector_db.similarity_search(question: "test query", k: 5)
        assert_nil @qdrant_stub.last_filter
      end
    end
  end

  class QdrantStub
    attr_reader :last_filter

    def create_default_schema(vector_size: 1536)
      return ""
    end

    def destroy_default_schema
      true
    end

    def add_texts(texts:, ids:, payload:)
      if (texts[0].length > 1500)
        raise "Error"
      end
    end

    def remove_texts(ids:)
      true
    end

    def ask_with_filter(query:, k: 20, filter: nil)
      ["test"]
    end

    def similarity_search(query:, k: 4, filter: nil)
      @last_filter = filter
      [{ "payload" => { "issue_id" => 1 }, "score" => 0.9 }]
    end
  end
end
