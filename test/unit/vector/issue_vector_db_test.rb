require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/vector/issue_vector_db"
require "redmine_ai_helper/vector/issue_content_analyzer"

class RedmineAiHelper::Vector::IssueVectorDbTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :journals

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

    context "hybrid content generation" do
      setup do
        @mock_analyzer = mock("IssueContentAnalyzer")
        @analysis_result = {
          summary: "This is a test summary describing the issue problem and solution.",
          keywords: ["authentication", "login", "API", "timeout"]
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

      should "fallback to raw content when analyzer fails" do
        # Mock IssueContentAnalyzer to raise an error
        @mock_analyzer.expects(:analyze).with(@issue).raises(StandardError.new("LLM call failed"))
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        # Verify fallback to raw content (current behavior)
        assert content.include?(@issue.subject), "Content should include the issue subject"
        # Verify it doesn't have the structured format
        assert_no_match(/^Summary:/, content)
        assert_no_match(/^Keywords:/, content)
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
        # Create a long description
        long_description = "A" * 600
        @issue.description = long_description

        @mock_analyzer.expects(:analyze).with(@issue).returns(@analysis_result)
        RedmineAiHelper::Vector::IssueContentAnalyzer.expects(:new).returns(@mock_analyzer)

        json_data = @vector_db.data_to_json(@issue)
        content = json_data[:content]

        # Extract the Description section from content
        description_match = content.match(/Description:\s*(.+)/m)
        assert description_match, "Content should have Description section"

        description_text = description_match[1].strip
        # Description should be truncated to 500 chars + "..."
        assert description_text.length <= 503, "Description should be truncated to 500 characters plus ellipsis"
        assert description_text.end_with?("..."), "Truncated description should end with ellipsis"
      end
    end
  end
end
