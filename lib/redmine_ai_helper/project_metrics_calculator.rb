# frozen_string_literal: true

require "redmine_ai_helper/logger"

module RedmineAiHelper
  # Calculates project health metrics (repository, issue, timing, workload, quality,
  # progress, member, update-frequency, estimation-accuracy, and attachment metrics)
  # for ProjectTools#get_metrics. Extracted from ProjectTools to keep that class within
  # the project's Metrics/ClassLength limit; behavior is unchanged.
  class ProjectMetricsCalculator
    include RedmineAiHelper::Logger

    # Calculate repository metrics for a project within a specified date range.
    # @param project [Project] The project to calculate metrics for.
    # @param start_date [Date, nil] Start date for metrics calculation.
    # @param end_date [Date, nil] End date for metrics calculation.
    # @return [Hash] A hash containing repository metrics.
    def calculate_repository_metrics(project, start_date: nil, end_date: nil)
      repositories = project.repositories
      if repositories.empty?
        ai_helper_logger.info "calculate_repository_metrics: no repository for project #{project.id}"
        return { repository_available: false }
      end

      changesets_scope = Changeset.joins(:repository).where(repositories: { project_id: project.id })
      if start_date && end_date
        changesets_scope = changesets_scope.where(committed_on: start_date.beginning_of_day..end_date.end_of_day)
      end

      changesets = changesets_scope
        .includes(:user, :repository)
        .order(committed_on: :desc)
        .limit(10000)
        .to_a

      repository_metrics_defaults = {
        commit_frequency: {},
        committer_distribution: {},
        commit_timeline: {},
        commit_size_metrics: {}
      }

      base_metrics = {
        repository_available: true,
        repository_info: extract_repository_info(repositories),
        period: {
          start_date: start_date,
          end_date: end_date
        },
        total_commits: changesets.size
      }

      if changesets.empty?
        ai_helper_logger.info "calculate_repository_metrics: no changesets for project #{project.id}"
        return base_metrics.merge(repository_metrics_defaults)
      end

      ai_helper_logger.info "calculate_repository_metrics: processing #{changesets.size} changesets for project #{project.id}"
      base_metrics.merge(
        commit_frequency: calculate_commit_frequency(changesets, start_date, end_date),
        committer_distribution: calculate_committer_distribution(changesets),
        commit_timeline: calculate_commit_timeline(changesets, start_date, end_date),
        commit_size_metrics: calculate_commit_size_metrics(changesets)
      )
    rescue ActiveRecord::RecordNotFound => e
      ai_helper_logger.error "calculate_repository_metrics record not found: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")
      {
        repository_available: true,
        error: "Repository data not found"
      }
    rescue => e
      ai_helper_logger.error "calculate_repository_metrics error: #{e.message}"
      ai_helper_logger.error e.backtrace.join("\n")
      {
        repository_available: true,
        error: e.message
      }
    end

    # Calculate issue counts broken down by status, priority, tracker, assignee, and author.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing issue statistics.
    def calculate_issue_statistics(issues)
      issue_list = issues.to_a

      open_issues = issue_list.select { |issue| !issue.status.is_closed? }
      closed_issues = issue_list.select { |issue| issue.status.is_closed? }

      by_priority = issue_list.group_by { |issue| issue.priority.name }.transform_values(&:count)
      by_tracker = issue_list.group_by { |issue| issue.tracker.name }.transform_values(&:count)
      by_status = issue_list.group_by { |issue| issue.status.name }.transform_values(&:count)
      by_assigned_to = issue_list.select { |issue| issue.assigned_to }.group_by { |issue| issue.assigned_to.name }.transform_values(&:count)
      by_author = issue_list.select { |issue| issue.author }.group_by { |issue| issue.author.name }.transform_values(&:count)

      {
        total_issues: issue_list.count,
        open_issues: open_issues.count,
        closed_issues: closed_issues.count,
        by_priority: by_priority,
        by_tracker: by_tracker,
        by_status: by_status,
        by_assigned_to: by_assigned_to,
        by_author: by_author
      }
    end

    # Calculate resolution-time and overdue statistics for a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing timing metrics.
    def calculate_timing_metrics(issues)
      issue_list = issues.to_a
      closed_issues = issue_list.select { |issue| issue.status.is_closed? }

      resolution_times = closed_issues.filter_map do |issue|
        next unless issue.closed_on && issue.created_on
        (issue.closed_on - issue.created_on) / 1.day
      end

      overdue_issues = issue_list.select do |issue|
        issue.due_date && issue.due_date < Date.current && !issue.status.is_closed?
      end

      issues_with_due_date = issue_list.select { |issue| issue.due_date }

      {
        average_resolution_time_days: resolution_times.empty? ? 0 : resolution_times.sum / resolution_times.size,
        median_resolution_time_days: resolution_times.empty? ? 0 : resolution_times.sort[resolution_times.size / 2],
        min_resolution_time_days: resolution_times.empty? ? 0 : resolution_times.min,
        max_resolution_time_days: resolution_times.empty? ? 0 : resolution_times.max,
        overdue_issues_count: overdue_issues.count,
        issues_with_due_date: issues_with_due_date.count,
        resolution_time_distribution: resolution_times.empty? ? {} : {
          under_1_day: resolution_times.count { |t| t < 1 },
          one_to_7_days: resolution_times.count { |t| t >= 1 && t < 7 },
          one_to_4_weeks: resolution_times.count { |t| t >= 7 && t < 28 },
          over_4_weeks: resolution_times.count { |t| t >= 28 }
        }
      }
    end

    # Calculate estimated vs. spent hours and estimation accuracy across a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing workload metrics.
    def calculate_workload_metrics(issues)
      issue_list = issues.to_a

      total_estimated_hours = issue_list.sum { |issue| issue.estimated_hours || 0 }
      total_spent_hours = issue_list.sum { |issue| issue.time_entries.sum(&:hours) }

      estimated_vs_actual = issue_list.filter_map do |issue|
        estimated = issue.estimated_hours
        spent = issue.time_entries.sum(&:hours)
        next unless estimated && estimated > 0 && spent > 0
        {
          issue_id: issue.id,
          estimated_hours: estimated,
          spent_hours: spent,
          variance_percentage: ((spent - estimated) / estimated * 100).round(2)
        }
      end

      issues_with_estimates = issue_list.select { |issue| issue.estimated_hours }
      issues_with_time_entries = issue_list.select { |issue| issue.time_entries.any? }

      {
        total_estimated_hours: total_estimated_hours,
        total_spent_hours: total_spent_hours,
        estimation_accuracy: total_estimated_hours > 0 ? ((total_spent_hours / total_estimated_hours) * 100).round(2) : 0,
        issues_with_estimates: issues_with_estimates.count,
        issues_with_time_entries: issues_with_time_entries.count,
        estimated_vs_actual_details: estimated_vs_actual,
        average_estimation_variance: estimated_vs_actual.empty? ? 0 : estimated_vs_actual.sum { |e| e[:variance_percentage] } / estimated_vs_actual.size
      }
    end

    # Calculate tracker distribution and reopened-issue statistics for a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing quality metrics.
    def calculate_quality_metrics(issues)
      issue_list = issues.to_a

      # Group issues by tracker for statistics
      by_tracker = issue_list.group_by { |issue| issue.tracker.name }.transform_values(&:count)

      # Count reopened issues by checking journal entries for status changes
      reopened_issues = issue_list.select do |issue|
        status_changes = issue.journals.joins(:details).where(journal_details: { property: "attr", prop_key: "status_id" })
        status_changes.count > 1
      end

      {
        by_tracker: by_tracker,
        tracker_ratios: by_tracker.transform_values { |count| issue_list.count > 0 ? (count.to_f / issue_list.count * 100).round(2) : 0 },
        reopened_issues_count: reopened_issues.count,
        reopened_ratio: issue_list.count > 0 ? (reopened_issues.count.to_f / issue_list.count * 100).round(2) : 0
      }
    end

    # Calculate completion-percentage and progress-distribution statistics for a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing progress metrics.
    def calculate_progress_metrics(issues)
      issue_list = issues.to_a

      total_done_ratio = issue_list.sum { |issue| issue.status.is_closed? ? 100 : (issue.done_ratio || 0) }
      issues_with_progress = issue_list.select { |issue| issue.status.is_closed? || (issue.done_ratio || 0) > 0 }

      not_started = issue_list.select { |issue| (issue.done_ratio || 0) == 0 && !issue.status.is_closed? }
      in_progress = issue_list.select { |issue| !issue.status.is_closed? && (ratio = (issue.done_ratio || 0); ratio > 0 && ratio < 100) }
      completed = issue_list.select { |issue| issue.status.is_closed? || (issue.done_ratio || 0) == 100 }

      {
        average_completion_percentage: issue_list.count > 0 ? (total_done_ratio.to_f / issue_list.count).round(2) : 0,
        issues_with_progress: issues_with_progress.count,
        completion_distribution: {
          not_started: not_started.count,
          in_progress: in_progress.count,
          completed: completed.count
        }
      }
    end

    # Calculate per-member workload distribution across assigned issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing member metrics.
    def calculate_member_metrics(issues)
      issue_list = issues.to_a

      assigned_issues = issue_list.select { |issue| issue.assigned_to }
      unassigned_issues = issue_list.select { |issue| !issue.assigned_to }

      members_workload = assigned_issues.group_by { |issue| issue.assigned_to }.map do |user, user_issues|
        total_progress = user_issues.sum { |issue| issue.done_ratio || 0 }
        average_progress = user_issues.count > 0 ? (total_progress.to_f / user_issues.count).round(2) : 0

        {
          user_name: user.name,
          user_id: user.id,
          assigned_issues: user_issues.count,
          average_progress: average_progress
        }
      end

      {
        members_workload: members_workload,
        unassigned_issues: unassigned_issues.count,
        total_active_members: members_workload.size,
        workload_balance: calculate_workload_balance(members_workload)
      }
    end

    # Calculate journal update frequency and recency statistics for a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing update frequency metrics.
    def calculate_update_frequency_metrics(issues)
      issue_list = issues.to_a
      now = Time.current

      update_stats = issue_list.map do |issue|
        journal_count = issue.journals.count
        last_update = issue.updated_on
        days_since_update = last_update ? ((now - last_update) / 1.day).to_i : nil

        {
          issue_id: issue.id,
          update_count: journal_count,
          days_since_last_update: days_since_update
        }
      end

      total_updates = update_stats.sum { |s| s[:update_count] }
      average_updates = issue_list.count > 0 ? (total_updates.to_f / issue_list.count).round(2) : 0

      within_week = update_stats.count { |s| s[:days_since_last_update] && s[:days_since_last_update] <= 7 }
      within_month = update_stats.count { |s| s[:days_since_last_update] && s[:days_since_last_update] <= 30 }
      over_month = update_stats.count { |s| s[:days_since_last_update] && s[:days_since_last_update] > 30 }

      actively_updated = update_stats.count { |s| s[:days_since_last_update] && s[:days_since_last_update] <= 14 }

      {
        average_updates_per_ticket: average_updates,
        total_updates: total_updates,
        update_recency_distribution: {
          within_1_week: within_week,
          within_1_month: within_month,
          over_1_month: over_month
        },
        actively_updated_tickets: actively_updated,
        active_update_ratio: issue_list.count > 0 ? (actively_updated.to_f / issue_list.count * 100).round(2) : 0
      }
    end

    # Calculate estimation-accuracy statistics (estimated vs. spent hours) per issue, tracker, and assignee.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing estimation accuracy metrics.
    def calculate_estimation_accuracy_metrics(issues)
      issue_list = issues.to_a

      issues_with_both = issue_list.select do |issue|
        estimated = issue.estimated_hours
        spent = issue.time_entries.sum(&:hours)
        estimated && estimated > 0 && spent > 0
      end

      return { accuracy_data_available: false } if issues_with_both.empty?

      accuracy_data = issues_with_both.map do |issue|
        estimated = issue.estimated_hours
        spent = issue.time_entries.sum(&:hours)
        accuracy = (spent / estimated * 100).round(2)
        variance = ((spent - estimated) / estimated * 100).round(2)

        {
          issue_id: issue.id,
          estimated_hours: estimated,
          spent_hours: spent,
          accuracy_percentage: accuracy,
          variance_percentage: variance,
          tracker: issue.tracker&.name,
          assignee: issue.assigned_to&.name
        }
      end

      total_accuracy = accuracy_data.sum { |d| d[:accuracy_percentage] } / accuracy_data.size
      overestimated = accuracy_data.count { |d| d[:variance_percentage] < -10 }
      underestimated = accuracy_data.count { |d| d[:variance_percentage] > 10 }
      accurate = accuracy_data.count { |d| d[:variance_percentage].abs <= 10 }

      by_tracker = accuracy_data.group_by { |d| d[:tracker] }.transform_values do |tracker_data|
        avg_accuracy = tracker_data.sum { |d| d[:accuracy_percentage] } / tracker_data.size
        {
          count: tracker_data.size,
          average_accuracy: avg_accuracy.round(2)
        }
      end

      by_assignee = accuracy_data.group_by { |d| d[:assignee] }.compact.transform_values do |assignee_data|
        avg_accuracy = assignee_data.sum { |d| d[:accuracy_percentage] } / assignee_data.size
        {
          count: assignee_data.size,
          average_accuracy: avg_accuracy.round(2)
        }
      end

      {
        accuracy_data_available: true,
        average_accuracy_percentage: total_accuracy.round(2),
        estimation_ratios: {
          overestimated_count: overestimated,
          underestimated_count: underestimated,
          accurate_count: accurate,
          overestimated_ratio: (overestimated.to_f / accuracy_data.size * 100).round(2),
          underestimated_ratio: (underestimated.to_f / accuracy_data.size * 100).round(2),
          accurate_ratio: (accurate.to_f / accuracy_data.size * 100).round(2)
        },
        accuracy_by_tracker: by_tracker,
        accuracy_by_assignee: by_assignee,
        total_analyzed_issues: accuracy_data.size
      }
    end

    # Calculate attachment count, size, and file-type distribution statistics for a set of issues.
    # @param issues [Array<Issue>, ActiveRecord::Relation] Issues to summarize.
    # @return [Hash] A hash containing attachment metrics.
    def calculate_attachment_metrics(issues)
      issue_list = issues.to_a

      issues_with_attachments = issue_list.select { |issue| issue.attachments.any? }
      total_attachments = issue_list.sum { |issue| issue.attachments.count }

      return { attachments_available: false } if total_attachments == 0

      all_attachments = issue_list.flat_map(&:attachments)
      total_size_bytes = all_attachments.sum(&:filesize)
      average_size_bytes = total_size_bytes / all_attachments.count

      file_type_stats = all_attachments.group_by do |attachment|
        extension = File.extname(attachment.filename).downcase
        case extension
        when ".pdf"
          "PDF"
        when ".doc", ".docx", ".odt", ".rtf", ".txt"
          "Document"
        when ".xls", ".xlsx", ".ods", ".csv"
          "Spreadsheet"
        when ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".svg"
          "Image"
        else
          "Other"
        end
      end.transform_values(&:count)

      large_files = all_attachments.select { |att| att.filesize > 10.megabytes }

      {
        attachments_available: true,
        document_attachment_rate: issue_list.count > 0 ? (issues_with_attachments.count.to_f / issue_list.count * 100).round(2) : 0,
        total_attachments: total_attachments,
        average_attachments_per_ticket: issue_list.count > 0 ? (total_attachments.to_f / issue_list.count).round(2) : 0,
        average_attachments_per_ticket_with_attachments: issues_with_attachments.count > 0 ? (total_attachments.to_f / issues_with_attachments.count).round(2) : 0,
        file_type_distribution: file_type_stats,
        file_size_statistics: {
          total_size_mb: (total_size_bytes.to_f / 1.megabyte).round(2),
          average_size_kb: (average_size_bytes.to_f / 1.kilobyte).round(2),
          large_files_count: large_files.count,
          large_files_ratio: (large_files.count.to_f / all_attachments.count * 100).round(2)
        }
      }
    end

    private

    def extract_repository_info(repositories)
      repositories.map do |repo|
        {
          id: repo.id,
          identifier: repo.identifier,
          type: repo.type,
          url: repo.url,
          is_default: repo.is_default
        }
      end
    end

    def calculate_commit_frequency(changesets, start_date, end_date)
      return {} if changesets.empty?

      if start_date && end_date
        total_days = (end_date - start_date).to_i + 1
      else
        oldest_commit = changesets.last.committed_on.to_date
        newest_commit = changesets.first.committed_on.to_date
        total_days = (newest_commit - oldest_commit).to_i + 1
      end

      total_days = 1 if total_days < 1
      total_commits = changesets.size

      {
        total_commits: total_commits,
        daily_average: (total_commits.to_f / total_days).round(2),
        weekly_average: (total_commits.to_f / total_days * 7).round(2),
        monthly_average: (total_commits.to_f / total_days * 30).round(2),
        period_days: total_days
      }
    end

    def calculate_committer_distribution(changesets)
      by_user = changesets
        .select { |cs| cs.user }
        .group_by { |cs| cs.user }
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .to_h

      by_committer = changesets
        .select { |cs| cs.user.nil? && cs.committer.present? }
        .group_by { |cs| cs.committer }
        .transform_values(&:count)
        .sort_by { |_, count| -count }
        .to_h

      mapped_users = changesets.count { |cs| cs.user.present? }
      unmapped_commits = changesets.count { |cs| cs.user.nil? }

      {
        by_user: by_user.map { |user, count| { user_id: user.id, user_name: user.name, commit_count: count } },
        by_committer_string: by_committer.map { |committer, count| { committer: committer, commit_count: count } },
        unique_users: by_user.size,
        unique_committers: by_committer.size,
        mapped_commits: mapped_users,
        unmapped_commits: unmapped_commits,
        mapping_rate: changesets.empty? ? 0 : (mapped_users.to_f / changesets.size * 100).round(2)
      }
    end

    def calculate_commit_timeline(changesets, _start_date = nil, _end_date = nil)
      by_date = changesets
        .group_by { |cs| cs.committed_on.to_date }
        .transform_values(&:count)
        .sort_by { |date, _| date }
        .to_h

      by_week = changesets
        .group_by { |cs| cs.committed_on.to_date.cweek }
        .transform_values(&:count)
        .sort_by { |week, _| week }
        .to_h

      by_weekday = changesets
        .group_by { |cs| cs.committed_on.strftime("%A") }
        .transform_values(&:count)

      by_hour = changesets
        .group_by { |cs| cs.committed_on.hour }
        .transform_values(&:count)
        .sort_by { |hour, _| hour }
        .to_h

      {
        by_date: by_date,
        by_week: by_week,
        by_weekday: by_weekday,
        by_hour: by_hour,
        most_active_date: by_date.max_by { |_, count| count }&.first,
        least_active_date: by_date.min_by { |_, count| count }&.first
      }
    end

    def calculate_commit_size_metrics(changesets)
      comment_lengths = changesets.map { |cs| cs.comments.to_s.length }
      return {} if comment_lengths.empty?

      {
        average_comment_length: (comment_lengths.sum.to_f / comment_lengths.size).round(2),
        median_comment_length: comment_lengths.sort[comment_lengths.size / 2],
        min_comment_length: comment_lengths.min,
        max_comment_length: comment_lengths.max,
        empty_comments_count: changesets.count { |cs| cs.comments.blank? },
        empty_comments_ratio: (changesets.count { |cs| cs.comments.blank? }.to_f / changesets.size * 100).round(2)
      }
    end

    def calculate_workload_balance(members_workload)
      return 0 if members_workload.empty?

      issue_counts = members_workload.map { |m| m[:assigned_issues] }
      average_workload = issue_counts.sum.to_f / issue_counts.size
      variance = issue_counts.sum { |count| (count - average_workload) ** 2 } / issue_counts.size

      {
        average_issues_per_member: average_workload.round(2),
        workload_variance: variance.round(2),
        max_workload: issue_counts.max,
        min_workload: issue_counts.min
      }
    end
  end
end
