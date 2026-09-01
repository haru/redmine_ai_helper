# frozen_string_literal: true

require_relative "../base_agent"
require "redmine_ai_helper/project_metrics_calculator"

module RedmineAiHelper
  module Agents
    # ProjectAgent is a specialized agent for handling Redmine project-related queries.
    class ProjectAgent < RedmineAiHelper::BaseAgent
      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        prompt = load_prompt("project_agent/backstory")
        content = prompt.format
        content
      end

      # Get available RubyLLM::Tool subclasses for this agent
      # @return [Array<Class>] Array of RubyLLM::Tool subclasses
      def available_tool_providers
        [ RedmineAiHelper::Tools::ProjectTools ]
      end

      # Generate comprehensive project health report
      # @param project [Project] The project object
      # @param options [Hash] Options for report generation
      # @param stream_proc [Proc] Optional callback proc for streaming content
      # @return [String] The project health report
      def project_health_report(project:, options: {}, stream_proc: nil) # rubocop:disable Lint/UnusedMethodArgument
        ai_helper_logger.debug "Generating project health report for project: #{project.name}"

        prompt = load_prompt("project_agent/health_report")
        project_tools = RedmineAiHelper::Tools::ProjectTools.new
        open_versions = project.shared_versions.open.order(created_on: :desc)

        metrics_list, analysis_instructions, analysis_focus, focus_guidance, report_sections =
          if open_versions.any?
            collect_version_metrics(project, project_tools, open_versions)
          else
            collect_time_period_metrics(project, project_tools)
          end

        project_settings = AiHelperProjectSetting.settings(project)
        health_report_instructions = project_settings.health_report_instructions

        prompt_text = prompt.format(
          project_id: project.id,
          analysis_focus: analysis_focus,
          analysis_instructions: analysis_instructions,
          report_sections: report_sections,
          focus_guidance: focus_guidance,
          health_report_instructions: (health_report_instructions.presence || "No specific instructions provided."),
          metrics: JSON.pretty_generate(metrics_list)
        )

        report_text = think_chat([ { role: "user", content: prompt_text } ], {}, stream_proc)
        save_health_report(project, report_text, metrics_list)
        report_text
      end

      # Generate comparative analysis of two health reports
      # @param old_report [AiHelperHealthReport] The older report
      # @param new_report [AiHelperHealthReport] The newer report
      # @param stream_proc [Proc] Optional callback for streaming
      # @return [String] Comparison analysis report
      def health_report_comparison(old_report:, new_report:, stream_proc: nil)
        ai_helper_logger.debug "Generating health report comparison for project: #{old_report.project.name}"

        unless old_report.project_id == new_report.project_id
          raise ArgumentError, "Reports must be from the same project"
        end

        if old_report.created_at > new_report.created_at
          old_report, new_report = new_report, old_report
        end

        locale = User.current.language.to_sym rescue :en
        prompt_key = locale == :ja ? "project_agent/health_report_comparison_ja" : "project_agent/health_report_comparison"
        prompt = load_prompt(prompt_key)

        time_span_days = ((new_report.created_at - old_report.created_at) / 1.day).round

        prompt_text = prompt.format(
          project_id: old_report.project_id,
          old_report_date: old_report.created_at.strftime("%Y-%m-%d %H:%M"),
          new_report_date: new_report.created_at.strftime("%Y-%m-%d %H:%M"),
          old_health_report: old_report.health_report,
          new_health_report: new_report.health_report,
          old_metrics: old_report.metrics,
          new_metrics: new_report.metrics,
          time_span_days: time_span_days
        )

        messages = [ { role: "user", content: prompt_text } ]

        comparison_text = think_chat(messages, {}, stream_proc)
        comparison_text
      end

      private

      def collect_version_metrics(project, project_tools, open_versions)
        analysis_instructions = load_prompt("project_agent/analysis_instructions_version").format
        analysis_focus = "Version-specific Analysis"
        focus_guidance = "Focus on version-specific actionable items and delivery success factors"
        report_sections = "Generate a separate section for each open version with detailed analysis"

        metrics_list = open_versions.map do |version|
          version_metrics = project_tools.get_metrics(project_id: project.id, version_id: version.id)
          info = { version_id: version.id, version_name: version.name, metrics: version_metrics }
          if version.project_id != project.id
            info[:shared_from_project] = { id: version.project_id, name: version.project.name, identifier: version.project.identifier }
            info[:sharing_mode] = version.sharing
          end
          info
        end

        append_repository_metrics(project, metrics_list)
        [ metrics_list, analysis_instructions, analysis_focus, focus_guidance, report_sections ]
      end

      def append_repository_metrics(project, metrics_list)
        one_week_ago = 1.week.ago.strftime("%Y-%m-%d")
        one_month_ago = 1.month.ago.strftime("%Y-%m-%d")
        today = Date.current.strftime("%Y-%m-%d")
        metrics_calculator = RedmineAiHelper::ProjectMetricsCalculator.new

        week_metrics = metrics_calculator.calculate_repository_metrics(project, start_date: Date.parse(one_week_ago), end_date: Date.parse(today))
        if week_metrics[:repository_available]
          metrics_list << { period_name: "Repository Activity (Last 1 Week)", period_description: "Repository activity analysis for the last 1 week", start_date: one_week_ago, end_date: today, metrics: { repository_metrics: week_metrics } }
        end

        month_metrics = metrics_calculator.calculate_repository_metrics(project, start_date: Date.parse(one_month_ago), end_date: Date.parse(today))
        if month_metrics[:repository_available]
          metrics_list << { period_name: "Repository Activity (Last 1 Month)", period_description: "Repository activity analysis for the last 1 month", start_date: one_month_ago, end_date: today, metrics: { repository_metrics: month_metrics } }
        end
      end

      def collect_time_period_metrics(project, project_tools)
        one_week_ago = 1.week.ago.strftime("%Y-%m-%d")
        one_month_ago = 1.month.ago.strftime("%Y-%m-%d")
        today = Date.current.strftime("%Y-%m-%d")

        analysis_instructions = load_prompt("project_agent/analysis_instructions_time_period").format(one_week_ago: one_week_ago, one_month_ago: one_month_ago, today: today)
        analysis_focus = "Time-period Analysis (Last Week & Last Month)"
        focus_guidance = "Focus on recent activity trends and identify patterns that can guide future project direction"
        report_sections = "Generate separate sections for 1-week and 1-month periods with comparative analysis"

        week_metrics = project_tools.get_metrics(project_id: project.id, start_date: one_week_ago, end_date: today)
        month_metrics = project_tools.get_metrics(project_id: project.id, start_date: one_month_ago, end_date: today)

        metrics_list = build_time_period_metrics_list(project, project_tools, week_metrics, month_metrics, one_week_ago, one_month_ago, today)
        [ metrics_list, analysis_instructions, analysis_focus, focus_guidance, report_sections ]
      end

      def build_time_period_metrics_list(project, project_tools, week_metrics, month_metrics, one_week_ago, one_month_ago, today)
        has_recent_data = week_metrics[:issue_statistics][:total_issues] > 0 || month_metrics[:issue_statistics][:total_issues] > 0
        return build_recent_metrics_list(project, project_tools, week_metrics, one_week_ago, today) unless has_recent_data

        [
          { period_name: "Last 1 Week", period_description: "Analysis for the last 1 week", start_date: one_week_ago, end_date: today, metrics: week_metrics },
          { period_name: "Last 1 Month", period_description: "Analysis for the last 1 month", start_date: one_month_ago, end_date: today, metrics: month_metrics }
        ]
      end

      def build_recent_metrics_list(project, project_tools, week_metrics, one_week_ago, today)
        all_time = project_tools.get_metrics(project_id: project.id)
        if all_time[:issue_statistics][:total_issues] > 0
          [ { period_name: "All Time Analysis", period_description: "Analysis for all periods (due to lack of recent data)", start_date: nil, end_date: nil, metrics: all_time } ]
        else
          [ { period_name: "Recent Activity", period_description: "Recent activity (no data)", start_date: one_week_ago, end_date: today, metrics: week_metrics } ]
        end
      end

      def save_health_report(project, report_text, metrics_list)
        report = AiHelperHealthReport.new
        report.project_id = project.id
        report.user_id = User.current.id
        report.health_report = report_text
        report.metrics = JSON.pretty_generate(metrics_list)
        report.save!
      end
    end
  end
end
