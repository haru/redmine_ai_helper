require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/vector/issue_vector_db"

class RedmineAiHelper::Vector::WikiVectorDbTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :journals, :wikis, :wiki_pages, :wiki_contents, :enabled_modules

  context "WikiVectorDb" do
    setup do
      @page = WikiPage.find(1)
      @vector_db = RedmineAiHelper::Vector::WikiVectorDb.new
    end

    should "return correct index name" do
      assert_equal "RedmineWiki", @vector_db.index_name
    end

    context "data_exists?" do
      should "return true when wiki page exists" do
        assert_equal true, @vector_db.data_exists?(@page.id)
      end

      should "return false when wiki page does not exist" do
        assert_equal false, @vector_db.data_exists?(999999)
      end
    end

    should "convert wiki data to JSON text" do
      json_data = @vector_db.data_to_json(@page)

      payload = json_data[:payload]

      assert_equal @page.id, payload[:wiki_id]
      assert_equal @page.project.name, payload[:project_name]
    end

    context "in_scope_object_ids" do
      setup do
        @page = WikiPage.find(1)
        @project = @page.wiki.project
        @project.enabled_modules.where(name: "ai_helper").destroy_all
      end

      should "include wiki pages whose project has ai_helper module enabled" do
        @project.enabled_modules.create!(name: "ai_helper")
        assert_includes @vector_db.in_scope_object_ids, @page.id
      end

      should "exclude wiki pages whose project does not have ai_helper module enabled" do
        assert_not_includes @vector_db.in_scope_object_ids, @page.id
      end

      should "exclude wiki pages that have been deleted" do
        @project.enabled_modules.create!(name: "ai_helper")
        page_id = @page.id
        @page.destroy!
        assert_not_includes @vector_db.in_scope_object_ids, page_id
      end

      should "exclude wiki pages whose project is not selected when register_all is OFF (US3/FR-011)" do
        @project.enabled_modules.create!(name: "ai_helper")
        AiHelperSetting.setting.update!(vector_register_all_projects: false, vector_target_project_ids: [])

        assert_not_includes @vector_db.in_scope_object_ids, @page.id
      end

      should "include wiki pages whose project is selected when register_all is OFF (US3/FR-011)" do
        @project.enabled_modules.create!(name: "ai_helper")
        AiHelperSetting.setting.update!(vector_register_all_projects: false, vector_target_project_ids: [ @project.id ])

        assert_includes @vector_db.in_scope_object_ids, @page.id
      end
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
