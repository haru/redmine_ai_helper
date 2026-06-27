require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/vector/issue_vector_db"
require "redmine_ai_helper/vector/issue_content_analyzer"

class RedmineAiHelper::Vector::IssueVectorDbTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :journals, :enabled_modules

  context "IssueVectorDb" do
    setup do
      @issue = Issue.find(1)
      @issue.assigned_to = User.find(2)
      @vector_db = RedmineAiHelper::Vector::IssueVectorDb.new
    end

    should "return correct index name" do
      assert_equal "RedmineIssue", @vector_db.index_name
    end

    should "convert issue data to JSON text" do
      json_data = @vector_db.data_to_json(@issue)

      payload = json_data[:payload]

      assert_equal @issue.id, payload[:issue_id]
      assert_equal @issue.project.name, payload[:project_name]
    end

    context "in_scope_object_ids" do
      setup do
        @project = Project.find(1)
        @issue = Issue.find(1)
        @project.enabled_modules.where(name: "ai_helper").destroy_all
      end

      should "include issues whose project has ai_helper module enabled" do
        @project.enabled_modules.create!(name: "ai_helper")
        assert_includes @vector_db.in_scope_object_ids, @issue.id
      end

      should "exclude issues whose project does not have ai_helper module enabled" do
        assert_not_includes @vector_db.in_scope_object_ids, @issue.id
      end

      should "exclude issues that have been deleted" do
        @project.enabled_modules.create!(name: "ai_helper")
        issue_id = @issue.id
        @issue.destroy!
        assert_not_includes @vector_db.in_scope_object_ids, issue_id
      end

      should "exclude issues whose project is not selected when register_all is OFF (US3/FR-011)" do
        @project.enabled_modules.create!(name: "ai_helper")
        AiHelperSetting.setting.update!(vector_register_all_projects: false, vector_target_project_ids: [])

        assert_not_includes @vector_db.in_scope_object_ids, @issue.id
      end

      should "include issues whose project is selected when register_all is OFF (US3/FR-011)" do
        @project.enabled_modules.create!(name: "ai_helper")
        AiHelperSetting.setting.update!(vector_register_all_projects: false, vector_target_project_ids: [ @project.id ])

        assert_includes @vector_db.in_scope_object_ids, @issue.id
      end
    end

    context "data_exists?" do
      should "return true when issue exists" do
        assert_equal true, @vector_db.data_exists?(@issue.id)
      end

      should "return false when issue does not exist" do
        assert_equal false, @vector_db.data_exists?(999999)
      end
    end

    context "payload_index_declarations" do
      should "return the 10-entry declaration list in stable order" do
        expected = [
          { field_name: "project_id",     field_schema: "integer" },
          { field_name: "tracker_id",     field_schema: "integer" },
          { field_name: "status_id",      field_schema: "integer" },
          { field_name: "priority_id",    field_schema: "integer" },
          { field_name: "author_id",      field_schema: "integer" },
          { field_name: "assigned_to_id", field_schema: "integer" },
          { field_name: "version_id",     field_schema: "integer" },
          { field_name: "created_on",     field_schema: "datetime" },
          { field_name: "updated_on",     field_schema: "datetime" },
          { field_name: "due_date",       field_schema: "datetime" }
        ]

        assert_equal expected, @vector_db.payload_index_declarations
      end

      should "declare only field names present in data_to_json payload (FR-003)" do
        # Stub analyzer so data_to_json runs without contacting the LLM.
        mock_analyzer = mock("IssueContentAnalyzer")
        mock_analyzer.stubs(:analyze).returns({ summary: "x", keywords: [] })
        RedmineAiHelper::Vector::IssueContentAnalyzer.stubs(:new).returns(mock_analyzer)

        payload = @vector_db.data_to_json(@issue)[:payload]
        @vector_db.payload_index_declarations.each do |decl|
          assert_includes payload.keys.map(&:to_s), decl[:field_name],
                          "Declared field #{decl[:field_name]} is missing from data_to_json payload"
        end
      end
    end

    context "hybrid content generation" do
      setup do
        @mock_analyzer = mock("IssueContentAnalyzer")
        @analysis_result = {
          summary: "This is a test summary describing the issue problem and solution.",
          keywords: [ "authentication", "login", "API", "timeout" ]
        }
      end

      should "generate structured content with summary and keywords" do
        # Mock IssueContentAnalyzer to return expected analysis result
        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        # Verify the content contains summary
        assert_match(/Summary:\s*This is a test summary describing the issue problem and solution\./, content)
        # Verify the content contains keywords
        assert_match(/Keywords:\s*authentication, login, API, timeout/, content)
      end

      should "raise error when analyzer fails (no fallback)" do
        @mock_analyzer.expects(:analyze).with(@issue).raises(StandardError.new("LLM call failed"))
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        assert_raises(StandardError, "LLM call failed") do
          @vector_db.data_to_json(@issue)
        end
      end

      should "include Title, Summary, Keywords, Description sections in content" do
        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        # Verify all required sections are present
        assert_match(/Summary:/, content, "Content should include Summary section")
        assert_match(/Keywords:/, content, "Content should include Keywords section")
        assert_match(/Title:/, content, "Content should include Title section")
        assert_match(/Description:/, content, "Content should include Description section")

        # Verify Title contains actual issue subject
        assert_match(/Title:\s*#{Regexp.escape(@issue.subject)}/, content)
      end

      should "truncate description to 500 characters" do
        long_description = "A" * 600
        @issue.description = long_description

        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        description_match = content.match(/Description:\s*(.+)/m)

        assert description_match, "Content should have Description section"

        description_text = description_match[1].strip
        assert_operator description_text.length, :<=, 503, "Description should be truncated to 500 characters plus ellipsis"
        assert description_text.end_with?("..."), "Truncated description should end with ellipsis"
      end

      should "truncate nil description to empty string" do
        @issue.description = nil

        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        assert_match(/Description:\s*$/, content)
      end
    end
  end
end
