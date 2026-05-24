require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/vector/issue_vector_db"

class RedmineAiHelper::Vector::WikiVectorDbTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :journals, :wikis, :wiki_pages, :wiki_contents

  context "WikiVectorDb" do
    setup do
      @page = WikiPage.find(1)
      @vector_db = RedmineAiHelper::Vector::WikiVectorDb.new
    end

    should "return correct index name" do
      assert_equal "RedmineWiki", @vector_db.index_name
    end

    should "convert wiki data to JSON text" do
      json_data = @vector_db.data_to_json(@page)

      payload = json_data[:payload]

      assert_equal @page.id, payload[:wiki_id]
      assert_equal @page.project.name, payload[:project_name]
    end

    context "payload_index_declarations" do
      should "return the 3-entry declaration list in stable order" do
        expected = [
          { field_name: "project_id", field_schema: "integer" },
          { field_name: "created_on", field_schema: "datetime" },
          { field_name: "updated_on", field_schema: "datetime" }
        ]

        assert_equal expected, @vector_db.payload_index_declarations
      end

      should "declare only field names present in data_to_json payload (FR-003)" do
        payload = @vector_db.data_to_json(@page)[:payload]
        @vector_db.payload_index_declarations.each do |decl|
          assert_includes payload.keys.map(&:to_s), decl[:field_name],
                          "Declared field #{decl[:field_name]} is missing from data_to_json payload"
        end
      end
    end
  end
end
