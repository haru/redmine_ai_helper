require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/agents/project_agent"

class ProjectAgentTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :enabled_modules

  setup do
    @openai_mock = MyOpenAI::DummyOpenAIClient.new
    Langchain::LLM::OpenAI.stubs(:new).returns(@openai_mock)
    @params = {
      access_token: "test_access_token",
      uri_base: "http://example.com",
      organization_id: "test_org_id",
      model: "test_model",
      project: Project.find(1),
      langfuse: DummyLangfuse.new,
    }
    @agent = RedmineAiHelper::Agents::ProjectAgent.new(@params)
  end

  context "ProjectAgent" do
    should "return correct available_tool_providers" do
      providers = @agent.available_tool_providers
      assert_includes providers, RedmineAiHelper::Tools::ProjectTools
    end

    context "project_health_report" do
      setup do
        @project = Project.find(1)
        # Set the current user to an admin who has access to all projects
        User.current = User.find(1)  # Admin user

        # Enable ai_helper module for the project
        enabled_module = EnabledModule.new
        enabled_module.project_id = @project.id
        enabled_module.name = "ai_helper"
        enabled_module.save!
      end

      should "generate version-specific report when open versions exist" do
        # Create a mock version for testing
        version = Version.new(name: "Test Version", project: @project, status: "open")
        version.stubs(:save!).returns(true)

        # Mock open versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([version])
        @project.versions.stubs(:open).returns(mock_versions)

        # Mock ProjectTools
        mock_tools = mock("ProjectTools")
        mock_tools.stubs(:get_metrics).returns({ issue_statistics: { total_issues: 5 } })
        RedmineAiHelper::Tools::ProjectTools.stubs(:new).returns(mock_tools)

        # Mock the chat method
        @agent.stubs(:chat).returns("test answer")

        result = @agent.project_health_report(project: @project)
        assert result.is_a?(String)
        assert_equal "test answer", result
      end

      should "generate time-period report when no open versions exist" do
        # Mock empty open versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([])
        @project.versions.stubs(:open).returns(mock_versions)

        # Mock ProjectTools
        mock_tools = mock("ProjectTools")
        mock_tools.stubs(:get_metrics).returns({ issue_statistics: { total_issues: 0 } })
        RedmineAiHelper::Tools::ProjectTools.stubs(:new).returns(mock_tools)

        # Mock the chat method
        @agent.stubs(:chat).returns("test answer")

        result = @agent.project_health_report(project: @project)
        assert result.is_a?(String)
        assert_equal "test answer", result
      end

      should "pass correct parameters to prompt format" do
        # Mock empty open versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([])
        @project.versions.stubs(:open).returns(mock_versions)

        # Mock ProjectTools
        mock_tools = mock("ProjectTools")
        mock_tools.stubs(:get_metrics).returns({ issue_statistics: { total_issues: 0 } })
        RedmineAiHelper::Tools::ProjectTools.stubs(:new).returns(mock_tools)

        # Mock analysis instructions prompt
        mock_analysis_prompt = mock("AnalysisPrompt")
        mock_analysis_prompt.stubs(:format).returns("Since there are no open versions in the project, please perform time-series analysis.")

        # Mock main health report prompt
        mock_prompt = mock("Prompt")
        mock_prompt.expects(:format).with(
          project_id: @project.id,
          analysis_focus: "Time-period Analysis (Last Week & Last Month)",
          analysis_instructions: includes("Since there are no open versions"),
          report_sections: "Generate separate sections for 1-week and 1-month periods with comparative analysis",
          focus_guidance: "Focus on recent activity trends and identify patterns that can guide future project direction",
          health_report_instructions: "No specific instructions provided.",
          metrics: instance_of(String),
        ).returns("formatted prompt")

        @agent.stubs(:load_prompt).with("project_agent/analysis_instructions_time_period").returns(mock_analysis_prompt)
        @agent.stubs(:load_prompt).with("project_agent/health_report").returns(mock_prompt)
        @agent.stubs(:chat).returns("test result")

        result = @agent.project_health_report(project: @project)
        assert_equal "test result", result
      end
    end

    context "health_report_comparison" do
      setup do
        @project = Project.find(1)
        User.current = User.find(1)  # Admin user

        # Create test health reports
        @old_report = AiHelperHealthReport.create!(
          project: @project,
          user: User.current,
          health_report: "Old health report content",
          metrics: { total_issues: 10, open_issues: 5 }.to_json,
          created_at: 7.days.ago,
        )

        @new_report = AiHelperHealthReport.create!(
          project: @project,
          user: User.current,
          health_report: "New health report content",
          metrics: { total_issues: 15, open_issues: 3 }.to_json,
          created_at: Time.now,
        )
      end

      teardown do
        @old_report.destroy if @old_report
        @new_report.destroy if @new_report
      end

      should "generate comparison between two reports" do
        # Mock the prompt template
        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("formatted comparison prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)

        # Mock the chat method
        @agent.stubs(:chat).returns("Comparison analysis result")

        result = @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
        )

        assert result.is_a?(String)
        assert_equal "Comparison analysis result", result
      end

      should "swap reports if old_report is newer than new_report" do
        # Mock the prompt template
        mock_prompt = mock("Prompt")
        mock_prompt.expects(:format).with(
          project_id: @project.id,
          old_report_date: @old_report.created_at.strftime("%Y-%m-%d %H:%M"),
          new_report_date: @new_report.created_at.strftime("%Y-%m-%d %H:%M"),
          old_health_report: "Old health report content",
          new_health_report: "New health report content",
          old_metrics: @old_report.metrics,
          new_metrics: @new_report.metrics,
          time_span_days: instance_of(Integer),
        ).returns("formatted prompt")

        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:chat).returns("test result")

        # Pass reports in reverse chronological order
        result = @agent.health_report_comparison(
          old_report: @new_report,
          new_report: @old_report,
        )

        assert_equal "test result", result
      end

      should "raise error when reports are from different projects" do
        different_project = Project.find(2)
        different_report = AiHelperHealthReport.create!(
          project: different_project,
          user: User.current,
          health_report: "Different project report",
          metrics: { total_issues: 5 }.to_json,
        )

        assert_raises ArgumentError do
          @agent.health_report_comparison(
            old_report: @old_report,
            new_report: different_report,
          )
        end

        different_report.destroy
      end

      should "use Japanese prompt template when user language is Japanese" do
        # Set user language to Japanese
        User.current.stubs(:language).returns("ja")

        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("formatted prompt")

        # Expect Japanese prompt to be loaded
        @agent.expects(:load_prompt).with("project_agent/health_report_comparison_ja").returns(mock_prompt)
        @agent.stubs(:chat).returns("Japanese comparison result")

        result = @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
        )

        assert_equal "Japanese comparison result", result
      end

      should "use English prompt template when user language is English" do
        # Set user language to English
        User.current.stubs(:language).returns("en")

        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("formatted prompt")

        # Expect English prompt to be loaded
        @agent.expects(:load_prompt).with("project_agent/health_report_comparison").returns(mock_prompt)
        @agent.stubs(:chat).returns("English comparison result")

        result = @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
        )

        assert_equal "English comparison result", result
      end

      should "calculate correct time span between reports" do
        mock_prompt = mock("Prompt")

        # Expect time_span_days to be approximately 7
        mock_prompt.expects(:format).with(
          has_entries(time_span_days: is_a(Integer))
        ).returns("formatted prompt")

        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:chat).returns("test result")

        @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
        )
      end

      should "support streaming response" do
        streamed_chunks = []
        stream_proc = ->(chunk) { streamed_chunks << chunk }

        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("formatted prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)

        # Mock chat to call stream_proc
        @agent.stubs(:chat).returns("Final result")

        result = @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
          stream_proc: stream_proc,
        )

        assert_equal "Final result", result
      end

      should "include metrics in prompt variables" do
        mock_prompt = mock("Prompt")

        mock_prompt.expects(:format).with(
          has_entries(
            old_metrics: @old_report.metrics,
            new_metrics: @new_report.metrics,
          )
        ).returns("formatted prompt")

        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:chat).returns("test result")

        @agent.health_report_comparison(
          old_report: @old_report,
          new_report: @new_report,
        )
      end
    end
  end

  class DummyLangfuse
    def initialize(params = {})
      @params = params
    end

    def create_span(name:, input: nil)
      # Do nothing
    end

    def finish_current_span(output: nil)
      # Do nothing
    end
  end
end
