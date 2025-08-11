require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/issue_agent"

class RedmineAiHelper::Agents::IssueAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations

  context "IssueAgent" do
    setup do
      @project = Project.find(1)
      @user = User.find(1)
      @issue = Issue.find(1)
      @langfuse = RedmineAiHelper::LangfuseUtil::LangfuseWrapper.new(input: "Test input for Langfuse")
      @agent = RedmineAiHelper::Agents::IssueAgent.new(project: @project, langfuse: @langfuse)
    end

    should "generate backstory including issue properties" do
      backstory = @agent.backstory
      assert_match /issue properties are available/, backstory
      assert_match /Project ID: #{@project.id}/, backstory
    end

    should "include vector tools when vector db is enabled" do
      AiHelperSetting.any_instance.stubs(:vector_search_enabled).returns(true)
      tools = @agent.available_tool_providers
      assert_includes tools, RedmineAiHelper::Tools::VectorTools
      assert_includes tools, RedmineAiHelper::Tools::IssueTools
      assert_includes tools, RedmineAiHelper::Tools::ProjectTools
    end

    should "not include vector tools when vector db is disabled" do
      AiHelperSetting.any_instance.stubs(:vector_search_enabled).returns(false)
      tools = @agent.available_tool_providers
      assert_not_includes tools, RedmineAiHelper::Tools::VectorTools
      assert_includes tools, RedmineAiHelper::Tools::IssueTools
      assert_includes tools, RedmineAiHelper::Tools::ProjectTools
    end

    should "generate issue summary for visible issue" do
      @issue.stubs(:visible?).returns(true)

      # Set up mock prompt
      mock_prompt = mock("Prompt")
      mock_prompt.stubs(:format).returns("Summarize this issue")
      @agent.stubs(:load_prompt).with("issue_agent/summary").returns(mock_prompt)

      # Mock chat method
      @agent.stubs(:chat).returns("This is a summary of the issue.")

      result = @agent.issue_summary(issue: @issue)
      assert_equal "This is a summary of the issue.", result
    end

    should "deny access for non-visible issue" do
      @issue.stubs(:visible?).returns(false)
      result = @agent.issue_summary(issue: @issue)
      assert_equal "Permission denied", result
    end

    should "generate issue properties string" do
      RedmineAiHelper::Tools::IssueTools.any_instance.stubs(:capable_issue_properties).returns({
        "priority" => ["High", "Normal", "Low"],
        "status" => ["New", "In Progress", "Resolved"],
      })

      issue_properties = @agent.send(:issue_properties)

      assert_match /The following issue properties are available/, issue_properties
      assert_match /Project ID: #{@project.id}/, issue_properties
      assert_match /"priority"/, issue_properties
      assert_match /"status"/, issue_properties
    end

    context "generate_issue_reply" do
      should "generate reply for visible issue" do
        @issue.stubs(:visible?).returns(true)

        # Set up mock prompt
        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("Generate a reply for this issue")
        @agent.stubs(:load_prompt).with("issue_agent/generate_reply").returns(mock_prompt)

        # Mock chat method
        @agent.stubs(:chat).returns("This is a generated reply.")

        result = @agent.generate_issue_reply(issue: @issue, instructions: "Please provide a detailed response.")
        assert_equal "This is a generated reply.", result
      end

      should "deny access for non-visible issue" do
        @issue.stubs(:visible?).returns(false)
        result = @agent.generate_issue_reply(issue: @issue, instructions: "Please provide a detailed response.")
        assert_equal "Permission denied", result
      end
      should "format instructions correctly in the prompt" do
        @issue.stubs(:visible?).returns(true)
        setting = AiHelperProjectSetting.settings(@issue.project)
        setting.issue_draft_instructions = "Draft instructions for the issue."
        setting.save!
        mock_prompt = mock("Prompt")
        mock_prompt.expects(:format).with(
          issue: instance_of(String),
          instructions: "Please provide a detailed response.",
          issue_draft_instructions: "Draft instructions for the issue.",
          format: Setting.text_formatting,
        ).returns("Generate a reply for this issue with instructions.")
        @agent.stubs(:load_prompt).with("issue_agent/generate_reply").returns(mock_prompt)

        @agent.stubs(:chat).returns("This is a generated reply.")

        result = @agent.generate_issue_reply(issue: @issue, instructions: "Please provide a detailed response.")
        assert_equal "This is a generated reply.", result
      end
    end

    context "generate_sub_issues_draft" do
      setup do
        Langchain::OutputParsers::OutputFixingParser.stubs(:from_llm).returns(DummyFixParser.new)

        @agent.stubs(:chat).returns("This is a generated reply.")
        User.current = User.find(1)
      end
      should "generate sub issues for visible issue" do
        issue = Issue.find(1)

        subissues = @agent.generate_sub_issues_draft(issue: issue, instructions: "Create sub issues based on this issue.")

        assert subissues
      end
    end

    context "find_similar_issues" do
      setup do
        @mock_vector_tools = mock("VectorTools")
        RedmineAiHelper::Tools::VectorTools.stubs(:new).returns(@mock_vector_tools)
        @mock_setting = mock("AiHelperSetting")
        @mock_setting.stubs(:vector_search_enabled).returns(true)
        AiHelperSetting.stubs(:vector_search_enabled?).returns(true)
      end

      should "return empty array if issue not visible" do
        @issue.stubs(:visible?).returns(false)
        
        result = @agent.find_similar_issues(issue: @issue)
        
        assert_equal [], result
      end

      should "return empty array if vector search not enabled" do
        AiHelperSetting.stubs(:vector_search_enabled?).returns(false)
        
        result = @agent.find_similar_issues(issue: @issue)
        
        assert_equal [], result
      end

      should "call VectorTools with correct parameters" do
        @issue.stubs(:visible?).returns(true)
        similar_issues_data = [
          {
            id: 2,
            subject: "Similar issue",
            similarity_score: 85.0
          }
        ]
        
        @mock_vector_tools.expects(:find_similar_issues)
                         .with(issue_id: @issue.id, k: 10)
                         .returns(similar_issues_data)
        
        result = @agent.find_similar_issues(issue: @issue)
        
        assert_equal similar_issues_data, result
      end

      should "handle errors from VectorTools gracefully" do
        @issue.stubs(:visible?).returns(true)
        @mock_vector_tools.stubs(:find_similar_issues).raises(StandardError.new("Vector search failed"))
        
        # Should log error and re-raise (just check that logging happens)
        mock_logger = mock("logger")
        mock_logger.stubs(:error)  # Allow any error logging
        @agent.stubs(:ai_helper_logger).returns(mock_logger)
        
        assert_raises(StandardError) do
          @agent.find_similar_issues(issue: @issue)
        end
      end

      should "log debug message with results count" do
        @issue.stubs(:visible?).returns(true)
        similar_issues_data = [{id: 2}, {id: 3}]
        @mock_vector_tools.stubs(:find_similar_issues).returns(similar_issues_data)
        
        mock_logger = mock("logger")
        mock_logger.expects(:debug).with("Found 2 similar issues for issue #{@issue.id}")
        @agent.stubs(:ai_helper_logger).returns(mock_logger)
        
        result = @agent.find_similar_issues(issue: @issue)
        
        assert_equal similar_issues_data, result
      end
    end
  end

  class DummyFixParser
    def parse(text)
      { "sub_issues" => [{ "subject" => "Dummy Sub Issue", "description" => "This is a dummy sub issue description." }] }
    end

    def get_format
      # Format is a simple string
      "string"
    end
  end
end
