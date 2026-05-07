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
  end
end
