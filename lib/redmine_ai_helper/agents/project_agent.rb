# frozen_string_literal: true
require_relative "../base_agent"

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

      # Get available tool providers for this agent
      # @return [Array<Class>] Array of tool provider classes
      def available_tool_providers
        [RedmineAiHelper::Tools::ProjectTools]
      end

      # Generate comprehensive project health report
      # @param project [Project] The project object
      # @param options [Hash] Options for report generation
      # @param stream_proc [Proc] Optional callback proc for streaming content
      # @return [String] The project health report
      def project_health_report(project:, options: {}, stream_proc: nil)
        ai_helper_logger.debug "Generating project health report for project: #{project.name}"

        prompt = load_prompt("project_agent/health_report")

        project_tools = RedmineAiHelper::Tools::ProjectTools.new

        # Check if there are any open versions in the project
        open_versions = project.shared_versions.open.order(created_on: :desc)
        metrics_list = []

        if open_versions.any?
          # Generate version-specific reports
          analysis_instructions_prompt = load_prompt("project_agent/analysis_instructions_version")
          analysis_instructions = analysis_instructions_prompt.format

          analysis_focus = "Version-specific Analysis"
          focus_guidance = "Focus on version-specific actionable items and delivery success factors"
          report_sections = "Generate a separate section for each open version with detailed analysis"

          open_versions.each do |version|
            version_metrics = project_tools.get_metrics(
              project_id: project.id,
              version_id: version.id,
            )

            # Determine if this is a shared version from another project
            is_shared = version.project_id != project.id
            version_info = {
              version_id: version.id,
              version_name: version.name,
              metrics: version_metrics,
            }

            # Add sharing information if it's a shared version
            if is_shared
              version_info[:shared_from_project] = {
                id: version.project_id,
                name: version.project.name,
                identifier: version.project.identifier,
              }
              version_info[:sharing_mode] = version.sharing
            end

            metrics_list << version_info
          end

          # Add separate repository activity sections for Pattern 1
          # Since version-specific metrics don't include repository data (to avoid duplication),
          # we add explicit repository analysis for the last 1 week and 1 month here.

          # Get date variables
          one_week_ago = 1.week.ago.strftime("%Y-%m-%d")
          one_month_ago = 1.month.ago.strftime("%Y-%m-%d")
          today = Date.current.strftime("%Y-%m-%d")

          # 1. Last 1 Week Repository Activity
          one_week_repo_metrics = project_tools.calculate_repository_metrics(
            project,
            start_date: Date.parse(one_week_ago),
            end_date: Date.parse(today)
          )

          if one_week_repo_metrics[:repository_available]
            metrics_list << {
              period_name: "Repository Activity (Last 1 Week)",
              period_description: "Repository activity analysis for the last 1 week",
              start_date: one_week_ago,
              end_date: today,
              metrics: { repository_metrics: one_week_repo_metrics }
            }
          end

          # 2. Last 1 Month Repository Activity
          one_month_repo_metrics = project_tools.calculate_repository_metrics(
            project,
            start_date: Date.parse(one_month_ago),
            end_date: Date.parse(today)
          )

          if one_month_repo_metrics[:repository_available]
            metrics_list << {
              period_name: "Repository Activity (Last 1 Month)",
              period_description: "Repository activity analysis for the last 1 month",
              start_date: one_month_ago,
              end_date: today,
              metrics: { repository_metrics: one_month_repo_metrics }
            }
          end
        else
          # Generate time-period based reports (last 1 week and last 1 month)
          # Get date variables first
          one_week_ago = 1.week.ago.strftime("%Y-%m-%d")
          one_month_ago = 1.month.ago.strftime("%Y-%m-%d")
          today = Date.current.strftime("%Y-%m-%d")

          analysis_instructions_prompt = load_prompt("project_agent/analysis_instructions_time_period")
          analysis_instructions = analysis_instructions_prompt.format(
            one_week_ago: one_week_ago,
            one_month_ago: one_month_ago,
            today: today,
          )

          analysis_focus = "Time-period Analysis (Last Week & Last Month)"
          focus_guidance = "Focus on recent activity trends and identify patterns that can guide future project direction"
          report_sections = "Generate separate sections for 1-week and 1-month periods with comparative analysis"

          # Try to get metrics for 1 week
          one_week_metrics = project_tools.get_metrics(
            project_id: project.id,
            start_date: one_week_ago,
            end_date: today,
          )

          # Try to get metrics for 1 month
          one_month_metrics = project_tools.get_metrics(
            project_id: project.id,
            start_date: one_month_ago,
            end_date: today,
          )

          # Check if we have any meaningful data (any issues created in these periods)
          has_recent_data = one_week_metrics[:issue_statistics][:total_issues] > 0 ||
                            one_month_metrics[:issue_statistics][:total_issues] > 0

          # If no recent data, fall back to all-time metrics
          unless has_recent_data
            all_time_metrics = project_tools.get_metrics(
              project_id: project.id,
            )

            # If we have all-time data, use it; otherwise keep the empty recent metrics
            if all_time_metrics[:issue_statistics][:total_issues] > 0
              metrics_list << {
                period_name: "All Time Analysis",
                period_description: "Analysis for all periods (due to lack of recent data)",
                start_date: nil,
                end_date: nil,
                metrics: all_time_metrics,
              }
            else
              # No data at all - add empty metrics for display
              metrics_list << {
                period_name: "Recent Activity",
                period_description: "Recent activity (no data)",
                start_date: one_week_ago,
                end_date: today,
                metrics: one_week_metrics,
              }
            end
          else
            # Add metrics for both periods
            metrics_list << {
              period_name: "Last 1 Week",
              period_description: "Analysis for the last 1 week",
              start_date: one_week_ago,
              end_date: today,
              metrics: one_week_metrics,
            }

            metrics_list << {
              period_name: "Last 1 Month",
              period_description: "Analysis for the last 1 month",
              start_date: one_month_ago,
              end_date: today,
              metrics: one_month_metrics,
            }
          end
        end

        # Get project-specific health report instructions
        project_settings = AiHelperProjectSetting.settings(project)
        health_report_instructions = project_settings.health_report_instructions

        prompt_text = prompt.format(
          project_id: project.id,
          analysis_focus: analysis_focus,
          analysis_instructions: analysis_instructions,
          report_sections: report_sections,
          focus_guidance: focus_guidance,
          health_report_instructions: health_report_instructions.present? ? health_report_instructions : "No specific instructions provided.",
          metrics: JSON.pretty_generate(metrics_list),
        )

        messages = [{ role: "user", content: prompt_text }]

        report_text = chat(messages, {}, stream_proc)

        # Save health report to database
        report = AiHelperHealthReport.new
        report.project_id = project.id
        report.user_id = User.current.id
        report.health_report = report_text
        report.metrics = JSON.pretty_generate(metrics_list)
        report.save!

        report_text
      end

      # Generate comparative analysis of two health reports
      # @param old_report [AiHelperHealthReport] The older report
      # @param new_report [AiHelperHealthReport] The newer report
      # @param stream_proc [Proc] Optional callback for streaming
      # @return [String] Comparison analysis report
      def health_report_comparison(old_report:, new_report:, stream_proc: nil)
        ai_helper_logger.debug "Generating health report comparison for project: #{old_report.project.name}"

        # Validate reports are from the same project
        unless old_report.project_id == new_report.project_id
          raise ArgumentError, "Reports must be from the same project"
        end

        # Ensure chronological order
        if old_report.created_at > new_report.created_at
          old_report, new_report = new_report, old_report
        end

        # Load prompt template based on locale
        locale = User.current.language.to_sym rescue :en
        prompt_key = locale == :ja ? "project_agent/health_report_comparison_ja" : "project_agent/health_report_comparison"
        prompt = load_prompt(prompt_key)

        # Calculate days between reports
        time_span_days = ((new_report.created_at - old_report.created_at) / 1.day).round

        # Set prompt variables
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

        messages = [{ role: "user", content: prompt_text }]

        comparison_text = chat(messages, {}, stream_proc)
        comparison_text
      end
    end
  end
end
