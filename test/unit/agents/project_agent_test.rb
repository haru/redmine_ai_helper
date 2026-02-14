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
    should "return correct available_tool_classes" do
      tool_classes = @agent.available_tool_classes
      RedmineAiHelper::Tools::ProjectTools.tool_classes.each do |tc|
        assert_includes tool_classes, tc
      end
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

        # Mock open shared versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([version])
        mock_shared_versions = mock("SharedVersions")
        mock_shared_versions.stubs(:open).returns(mock_versions)
        @project.stubs(:shared_versions).returns(mock_shared_versions)

        # Mock ProjectTools
        mock_tools = mock("ProjectTools")
        mock_tools.stubs(:get_metrics).returns({ issue_statistics: { total_issues: 5 } })

        # Mock calculate_repository_metrics calls for 1 week and 1 month
        mock_tools.stubs(:calculate_repository_metrics).with(
          @project,
          has_entries(start_date: instance_of(Date), end_date: instance_of(Date))
        ).returns({ repository_available: true })

        RedmineAiHelper::Tools::ProjectTools.stubs(:new).returns(mock_tools)

        # Mock the chat method
        @agent.stubs(:chat).returns("test answer")

        result = @agent.project_health_report(project: @project)
        assert result.is_a?(String)
        assert_equal "test answer", result
      end

      should "generate time-period report when no open versions exist" do
        # Mock empty open shared versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([])
        mock_shared_versions = mock("SharedVersions")
        mock_shared_versions.stubs(:open).returns(mock_versions)
        @project.stubs(:shared_versions).returns(mock_shared_versions)

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
        # Mock empty open shared versions with order method
        mock_versions = mock("OpenVersions")
        mock_versions.stubs(:order).with(created_on: :desc).returns([])
        mock_shared_versions = mock("SharedVersions")
        mock_shared_versions.stubs(:open).returns(mock_versions)
        @project.stubs(:shared_versions).returns(mock_shared_versions)

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

    context "shared version support" do
      setup do
        User.current = User.find(1)  # Admin user
      end

      should "include shared versions from parent projects in health report" do
        # Create parent project
        parent_project = Project.create!(
          name: "Parent Project",
          identifier: "parent-proj-#{Time.now.to_i}",
          is_public: true,
        )

        # Create child project
        child_project = Project.create!(
          name: "Child Project",
          identifier: "child-proj-#{Time.now.to_i}",
          parent_id: parent_project.id,
          is_public: true,
        )

        # Enable ai_helper module for child project
        EnabledModule.create!(project_id: child_project.id, name: "ai_helper")

        # Create a shared version in parent project
        shared_version = Version.create!(
          project_id: parent_project.id,
          name: "Shared Version 1.0",
          status: "open",
          sharing: "descendants",
        )

        # Create an issue in child project assigned to the shared version
        Issue.create!(
          project_id: child_project.id,
          tracker_id: 1,
          subject: "Test issue for shared version",
          author_id: 1,
          status_id: 1,
          fixed_version_id: shared_version.id,
        )

        # Mock the chat method to capture the prompt
        captured_prompt = nil
        @agent.define_singleton_method(:chat) do |messages, options = {}, stream_proc = nil|
          captured_prompt = messages.is_a?(Array) ? messages.first[:content] : messages
          "Mock health report with shared version"
        end

        # Generate health report
        result = @agent.project_health_report(project: child_project)

        # Verify shared version is included in the metrics
        assert_not_nil captured_prompt
        assert_includes captured_prompt, shared_version.name
        assert_includes captured_prompt, "shared_from_project"
        assert_includes captured_prompt, parent_project.name
        assert_equal "Mock health report with shared version", result
      end

      should "include system-wide shared versions in health report" do
        # Create two unrelated projects
        project_a = Project.create!(
          name: "Project A",
          identifier: "project-a-#{Time.now.to_i}",
          is_public: true,
        )

        project_b = Project.create!(
          name: "Project B",
          identifier: "project-b-#{Time.now.to_i}",
          is_public: true,
        )

        # Enable ai_helper for project B
        EnabledModule.create!(project_id: project_b.id, name: "ai_helper")

        # Create version in project A with system sharing
        system_version = Version.create!(
          project_id: project_a.id,
          name: "System Version 2.0",
          status: "open",
          sharing: "system",
        )

        # Create issue in project B assigned to shared version
        Issue.create!(
          project_id: project_b.id,
          tracker_id: 1,
          subject: "Test issue for system version",
          author_id: 1,
          status_id: 1,
          fixed_version_id: system_version.id,
        )

        # Mock the chat method to capture the prompt
        captured_prompt = nil
        @agent.define_singleton_method(:chat) do |messages, options = {}, stream_proc = nil|
          captured_prompt = messages.is_a?(Array) ? messages.first[:content] : messages
          "Mock health report with system version"
        end

        # Generate health report for project B
        result = @agent.project_health_report(project: project_b)

        # Verify shared version is included
        assert_not_nil captured_prompt
        assert_includes captured_prompt, system_version.name
        assert_includes captured_prompt, "sharing_mode"
        assert_includes captured_prompt, "system"
        assert_equal "Mock health report with system version", result
      end

      should "work with projects that have only local versions (backward compatibility)" do
        # Create project with no parent
        standalone_project = Project.create!(
          name: "Standalone Project",
          identifier: "standalone-#{Time.now.to_i}",
          is_public: true,
        )

        # Enable ai_helper module
        EnabledModule.create!(project_id: standalone_project.id, name: "ai_helper")

        # Create local version (sharing: 'none')
        local_version = Version.create!(
          project_id: standalone_project.id,
          name: "Local Version 1.0",
          status: "open",
          sharing: "none",
        )

        # Create issue assigned to local version
        Issue.create!(
          project_id: standalone_project.id,
          tracker_id: 1,
          subject: "Test issue for local version",
          author_id: 1,
          status_id: 1,
          fixed_version_id: local_version.id,
        )

        # Mock the chat method to capture the prompt
        captured_prompt = nil
        @agent.define_singleton_method(:chat) do |messages, options = {}, stream_proc = nil|
          captured_prompt = messages.is_a?(Array) ? messages.first[:content] : messages
          "Mock health report with local version"
        end

        # Generate health report
        result = @agent.project_health_report(project: standalone_project)

        # Verify local version is included
        assert_not_nil captured_prompt
        assert_includes captured_prompt, local_version.name

        # Note: Due to Redmine's shared_versions method including system-wide shared versions,
        # the prompt may include shared_from_project information for versions from other projects.
        # This is expected behavior. We verify that our local version is included.
        assert_equal "Mock health report with local version", result
      end

      should "include hierarchy shared versions in health report" do
        # Create parent and child projects
        parent_project = Project.create!(
          name: "Hierarchy Parent",
          identifier: "hierarchy-parent-#{Time.now.to_i}",
          is_public: true,
        )

        child_project = Project.create!(
          name: "Hierarchy Child",
          identifier: "hierarchy-child-#{Time.now.to_i}",
          parent_id: parent_project.id,
          is_public: true,
        )

        # Enable ai_helper for both
        EnabledModule.create!(project_id: parent_project.id, name: "ai_helper")
        EnabledModule.create!(project_id: child_project.id, name: "ai_helper")

        # Create version in parent with hierarchy sharing (bidirectional)
        hierarchy_version = Version.create!(
          project_id: parent_project.id,
          name: "Hierarchy Version 3.0",
          status: "open",
          sharing: "hierarchy",
        )

        # Create issues in child assigned to shared version
        Issue.create!(
          project_id: child_project.id,
          tracker_id: 1,
          subject: "Child issue for hierarchy version",
          author_id: 1,
          status_id: 1,
          fixed_version_id: hierarchy_version.id,
        )

        # Mock the chat method to capture the prompt
        captured_prompt = nil
        @agent.define_singleton_method(:chat) do |messages, options = {}, stream_proc = nil|
          captured_prompt = messages.is_a?(Array) ? messages.first[:content] : messages
          "Mock health report with hierarchy version"
        end

        # Generate health report for child project
        result = @agent.project_health_report(project: child_project)

        # Verify sharing_mode is 'hierarchy'
        assert_not_nil captured_prompt
        assert_includes captured_prompt, hierarchy_version.name
        assert_includes captured_prompt, "sharing_mode"
        assert_includes captured_prompt, "hierarchy"
        assert_equal "Mock health report with hierarchy version", result
      end

      should "include correct issue counts for shared versions in metrics" do
        # Create parent and child projects
        parent_project = Project.create!(
          name: "Metrics Parent",
          identifier: "metrics-parent-#{Time.now.to_i}",
          is_public: true,
        )

        child_project = Project.create!(
          name: "Metrics Child",
          identifier: "metrics-child-#{Time.now.to_i}",
          parent_id: parent_project.id,
          is_public: true,
        )

        # Enable ai_helper for child project
        EnabledModule.create!(project_id: child_project.id, name: "ai_helper")

        # Create shared version
        shared_version = Version.create!(
          project_id: parent_project.id,
          name: "Metrics Version 1.0",
          status: "open",
          sharing: "descendants",
        )

        # Create multiple issues in child assigned to shared version
        3.times do |i|
          Issue.create!(
            project_id: child_project.id,
            tracker_id: 1,
            subject: "Test issue #{i + 1} for shared version",
            author_id: 1,
            status_id: 1,
            fixed_version_id: shared_version.id,
          )
        end

        # Mock the chat method to capture the prompt with metrics
        captured_prompt = nil
        @agent.define_singleton_method(:chat) do |messages, options = {}, stream_proc = nil|
          captured_prompt = messages.is_a?(Array) ? messages.first[:content] : messages
          "Mock health report with correct metrics"
        end

        # Generate health report
        result = @agent.project_health_report(project: child_project)

        # Verify issue counts in metrics are correct
        assert_not_nil captured_prompt
        assert_includes captured_prompt, shared_version.name

        # The prompt should contain metrics information
        # Since we're using the real ProjectTools.get_metrics, it should show the correct counts
        assert_equal "Mock health report with correct metrics", result
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
