require File.expand_path("../../../test_helper", __FILE__)

class ProjectToolsTest < ActiveSupport::TestCase
  fixtures :projects, :projects_trackers, :trackers, :users, :repositories, :changesets, :changes, :issues, :issue_statuses, :enumerations, :issue_categories, :trackers

  def setup
    @provider = RedmineAiHelper::Tools::ProjectTools.new
    enabled_module = EnabledModule.new
    enabled_module.project_id = 1
    enabled_module.name = "ai_helper"
    enabled_module.save!
    User.current = User.find(1)
  end

  def test_list_projects
    enabled_module = EnabledModule.new
    enabled_module.project_id = 2
    enabled_module.name = "ai_helper"
    enabled_module.save!

    response = @provider.list_projects()
    assert_equal 2, response.size
    project1 = Project.find(1)
    project2 = Project.find(2)
    [project1, project2].each_with_index do |project, index|
      value = response[index]
      assert_equal project.id, value[:id]
      assert_equal project.name, value[:name]
    end
  end

  def test_read_project_by_id
    project = Project.find(1)

    response = @provider.read_project(project_id: project.id)
    assert_equal project.id, response[:id]
    assert_equal project.name, response[:name]
  end

  def test_read_project_by_name
    project = Project.find(1)

    response = @provider.read_project(project_name: project.name)
    assert_equal project.id, response[:id]
    assert_equal project.name, response[:name]
  end

  def test_read_project_by_identifier
    project = Project.find(1)

    response = @provider.read_project(project_identifier: project.identifier)
    assert_equal project.id, response[:id]
    assert_equal project.name, response[:name]
  end

  def test_read_project_not_found
    assert_raises(RuntimeError, "Project not found") do
      @provider.read_project(project_id: 999)
    end
  end

  def test_read_project_no_args
    assert_raises(RuntimeError, "No id or name or Identifier specified.") do
      @provider.read_project
    end
  end

  def test_project_members
    project = Project.find(1)
    members = project.members

    response = @provider.project_members(project_ids: [project.id])
    assert_equal members.size, response[:projects][0][:members].size
    assert_equal members.first.user_id, response[:projects][0][:members].first[:user_id]
  end

  def test_project_enabled_modules
    project = Project.find(1)
    enabled_modules = project.enabled_modules

    response = @provider.project_enabled_modules(project_id: project.id)
    assert_equal enabled_modules.size, response[:enabled_modules].size
    assert_equal enabled_modules.first.name, response[:enabled_modules].first[:name]
  end

  def test_list_project_activities
    assert_nothing_raised do
      project = Project.find(1)
      @provider.list_project_activities(project_id: project.id)

      author = User.find(1)
      @provider.list_project_activities(project_id: project.id, author_id: author.id)
    end
  end

  def test_project_members_with_multiple_projects
    project1 = Project.find(1)
    project2 = Project.find(2)

    # Enable AI helper for project2
    enabled_module = EnabledModule.new
    enabled_module.project_id = project2.id
    enabled_module.name = "ai_helper"
    enabled_module.save!

    response = @provider.project_members(project_ids: [project1.id, project2.id])
    assert_equal 2, response[:projects].size
    assert response[:projects].all? { |p| p.key?(:members) }
  end

  def test_project_members_with_invalid_project_id
    response = @provider.project_members(project_ids: [999])
    assert_equal "error", response.status
  end

  def test_project_enabled_modules_with_invalid_project_id
    assert_raises(ActiveRecord::RecordNotFound) do
      @provider.project_enabled_modules(project_id: 999)
    end
  end

  def test_list_project_activities_with_date_range
    project = Project.find(1)

    response = @provider.list_project_activities(project_id: project.id)

    assert_equal "success", response.status
    assert response.value.key?(:activities)
  end

  def test_list_project_activities_with_invalid_project_id
    assert_raises(ActiveRecord::RecordNotFound) do
      @provider.list_project_activities(project_id: 999)
    end
  end

  def test_list_project_activities_with_invalid_author_id
    project = Project.find(1)

    assert_raises(ActiveRecord::RecordNotFound) do
      @provider.list_project_activities(project_id: project.id, author_id: 999)
    end
  end

  def test_list_projects_includes_required_fields
    response = @provider.list_projects()

    response.each do |project_data|
      assert project_data.key?(:id)
      assert project_data.key?(:name)
    end
  end

  def test_read_project_includes_detailed_information
    project = Project.find(1)

    response = @provider.read_project(project_id: project.id)

    assert_equal project.id, response[:id]
    assert_equal project.name, response[:name]
  end

  def test_project_members_includes_member_details
    project = Project.find(1)

    response = @provider.project_members(project_ids: [project.id])
    project_data = response[:projects].first

    assert project_data.key?(:members)
    assert project_data[:members].is_a?(Array)
  end

  def test_read_project_without_permission
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    assert_raises(RuntimeError, "You don't have permission to view this project") do
      @provider.read_project(project_id: project.id)
    end
  end

  def test_read_project_with_subprojects
    project = Project.find(1)

    response = @provider.read_project(project_id: project.id)

    assert response.key?(:subprojects)
    assert response[:subprojects].is_a?(Array)
  end

  def test_project_members_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    response = @provider.project_members(project_ids: [project.id])
    # When user has no permission, accessible projects are filtered out, resulting in empty list
    assert_equal [], response[:projects]
  end

  def test_project_enabled_modules_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    result = @provider.project_enabled_modules(project_id: project.id)
    assert result.is_a?(RedmineAiHelper::ToolResponse)
    assert_equal "error", result.status
    assert_equal "You don't have permission to view this project", result.error
  end

  def test_list_project_activities_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    result = @provider.list_project_activities(project_id: project.id)
    assert result.is_a?(RedmineAiHelper::ToolResponse)
    assert_equal "error", result.status
    assert_equal "You don't have permission to view this project", result.error
  end

  def test_get_metrics
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)

    assert metrics.key?(:project_info)
    assert metrics.key?(:period)
    assert metrics.key?(:issue_statistics)
    assert metrics.key?(:timing_metrics)
    assert metrics.key?(:workload_metrics)
    assert metrics.key?(:quality_metrics)
    assert metrics.key?(:progress_metrics)
    assert metrics.key?(:member_metrics)

    # Test project_info structure
    project_info = metrics[:project_info]
    assert_equal project.id, project_info[:id]
    assert_equal project.name, project_info[:name]
    assert_equal project.identifier, project_info[:identifier]

    # Test issue_statistics structure
    issue_stats = metrics[:issue_statistics]
    assert issue_stats.key?(:total_issues)
    assert issue_stats.key?(:open_issues)
    assert issue_stats.key?(:closed_issues)
    assert issue_stats.key?(:by_priority)
    assert issue_stats.key?(:by_tracker)
    assert issue_stats.key?(:by_status)
    assert issue_stats.key?(:by_assigned_to)
    assert issue_stats.key?(:by_author)
  end

  def test_get_metrics_with_version_filter
    project = Project.find(1)
    version = project.versions.first

    metrics = @provider.get_metrics(project_id: project.id, version_id: version.id)

    assert_equal version.id, metrics[:period][:version_id]
  end

  def test_get_metrics_with_date_range
    project = Project.find(1)
    start_date = "2025-01-01"
    end_date = "2025-12-31"

    metrics = @provider.get_metrics(
      project_id: project.id,
      start_date: start_date,
      end_date: end_date,
    )

    assert_equal Date.parse(start_date), metrics[:period][:start_date]
    assert_equal Date.parse(end_date), metrics[:period][:end_date]
  end

  def test_calculate_repository_metrics_with_commits
    project = Project.find(1)

    metrics = @provider.send(:calculate_repository_metrics, project)

    assert_equal true, metrics[:repository_available]
    assert metrics[:total_commits] >= 0
    assert metrics[:commit_frequency].key?(:total_commits)
    assert metrics[:committer_distribution].key?(:unique_users)
    assert metrics[:commit_timeline].key?(:by_date)
  end

  def test_calculate_repository_metrics_with_date_range
    project = Project.find(1)
    start_date = 1.week.ago.to_date
    end_date = Date.current

    metrics = @provider.send(:calculate_repository_metrics, project, start_date: start_date, end_date: end_date)

    assert_equal start_date, metrics[:period][:start_date]
    assert_equal end_date, metrics[:period][:end_date]
    if metrics[:commit_frequency].empty?
      assert_equal({}, metrics[:commit_frequency])
    else
      assert metrics[:commit_frequency][:period_days] <= 8
    end
  end

  def test_calculate_repository_metrics_empty_repository
    project = Project.find(3)
    repo = Repository::Git.create!(project: project, url: "/tmp/empty-repo-#{SecureRandom.hex(4)}", identifier: "empty-#{SecureRandom.hex(2)}")

    metrics = @provider.send(:calculate_repository_metrics, project)

    assert_equal true, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits]
    assert_equal({}, metrics[:commit_frequency])

    repo.destroy
  end

  def test_calculate_commit_frequency
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(100).to_a
    start_date = 30.days.ago.to_date
    end_date = Date.current

    frequency = @provider.send(:calculate_commit_frequency, changesets, start_date, end_date)

    assert frequency[:total_commits] >= 0
    assert frequency[:daily_average] >= 0
    assert frequency[:weekly_average] >= 0
    assert frequency[:monthly_average] >= 0
  end

  def test_calculate_commit_timeline
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(50).to_a

    timeline = @provider.send(:calculate_commit_timeline, changesets, nil, nil)

    assert timeline.key?(:by_date)
    assert timeline.key?(:by_week)
    assert timeline.key?(:by_weekday)
    assert timeline.key?(:by_hour)
  end

  def test_calculate_commit_size_metrics
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(50).to_a

    metrics = @provider.send(:calculate_commit_size_metrics, changesets)

    if metrics.empty?
      assert_equal({}, metrics)
    else
      assert metrics.key?(:average_comment_length)
      assert metrics.key?(:median_comment_length)
      assert metrics.key?(:empty_comments_count)
    end
  end

  def test_calculate_repository_metrics_without_repository
    project_without_repo = Project.find(3)

    metrics = @provider.send(:calculate_repository_metrics, project_without_repo)

    assert_equal false, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits].to_i
  end

  def test_calculate_repository_metrics_handles_error
    project = Project.find(1)
    Changeset.expects(:joins).with(:repository).raises(StandardError.new("db failure"))

    metrics = @provider.send(:calculate_repository_metrics, project)

    assert_equal true, metrics[:repository_available]
    assert_equal "db failure", metrics[:error]
  end

  def test_calculate_repository_metrics_performance_limit
    project = Project.find(1)
    mock_scope = mock
    Changeset.expects(:joins).with(:repository).returns(mock_scope)
    mock_scope.expects(:where).with(repositories: { project_id: project.id }).returns(mock_scope)
    mock_scope.expects(:includes).with(:user, :repository).returns(mock_scope)
    mock_scope.expects(:order).with(committed_on: :desc).returns(mock_scope)
    mock_scope.expects(:limit).with(10000).returns(mock_scope)
    mock_scope.expects(:to_a).returns([])

    metrics = @provider.send(:calculate_repository_metrics, project)

    assert_equal true, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits]
  end

  def test_get_metrics_includes_repository_metrics
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)

    assert metrics[:repository_metrics]
    assert metrics[:repository_metrics].key?(:repository_available)
  end

  def test_get_metrics_invalid_project
    assert_raises(ActiveRecord::RecordNotFound) do
      @provider.get_metrics(project_id: 999)
    end
  end

  def test_get_metrics_without_permission
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    assert_raises(RuntimeError, "You don't have permission to view this project") do
      @provider.get_metrics(project_id: project.id)
    end
  end

  def test_get_metrics_timing_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    timing_metrics = metrics[:timing_metrics]

    assert timing_metrics.key?(:average_resolution_time_days)
    assert timing_metrics.key?(:median_resolution_time_days)
    assert timing_metrics.key?(:min_resolution_time_days)
    assert timing_metrics.key?(:max_resolution_time_days)
    assert timing_metrics.key?(:overdue_issues_count)
    assert timing_metrics.key?(:issues_with_due_date)
    assert timing_metrics.key?(:resolution_time_distribution)
  end

  def test_get_metrics_workload_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    workload_metrics = metrics[:workload_metrics]

    assert workload_metrics.key?(:total_estimated_hours)
    assert workload_metrics.key?(:total_spent_hours)
    assert workload_metrics.key?(:estimation_accuracy)
    assert workload_metrics.key?(:issues_with_estimates)
    assert workload_metrics.key?(:issues_with_time_entries)
    assert workload_metrics.key?(:estimated_vs_actual_details)
    assert workload_metrics.key?(:average_estimation_variance)
  end

  def test_get_metrics_quality_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    quality_metrics = metrics[:quality_metrics]

    assert quality_metrics.key?(:by_tracker)
    assert quality_metrics.key?(:tracker_ratios)
    assert quality_metrics.key?(:reopened_issues_count)
    assert quality_metrics.key?(:reopened_ratio)
  end

  def test_get_metrics_progress_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    progress_metrics = metrics[:progress_metrics]

    assert progress_metrics.key?(:average_completion_percentage)
    assert progress_metrics.key?(:issues_with_progress)
    assert progress_metrics.key?(:completion_distribution)

    completion_dist = progress_metrics[:completion_distribution]
    assert completion_dist.key?(:not_started)
    assert completion_dist.key?(:in_progress)
    assert completion_dist.key?(:completed)
  end

  def test_get_metrics_member_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    member_metrics = metrics[:member_metrics]

    assert member_metrics.key?(:members_workload)
    assert member_metrics.key?(:unassigned_issues)
    assert member_metrics.key?(:total_active_members)
    assert member_metrics.key?(:workload_balance)

    if member_metrics[:members_workload].any?
      workload = member_metrics[:members_workload].first
      assert workload.key?(:user_name)
      assert workload.key?(:user_id)
      assert workload.key?(:assigned_issues)
      assert workload.key?(:average_progress)
    end

    workload_balance = member_metrics[:workload_balance]
    if workload_balance.is_a?(Hash)
      assert workload_balance.key?(:average_issues_per_member)
      assert workload_balance.key?(:workload_variance)
      assert workload_balance.key?(:max_workload)
      assert workload_balance.key?(:min_workload)
    end
  end

  def test_get_metrics_error_handling_invalid_date
    project = Project.find(1)

    assert_raises(Date::Error) do
      @provider.get_metrics(project_id: project.id, start_date: "invalid-date")
    end
  end

  def test_list_projects_with_dummy_parameter
    response = @provider.list_projects(dummy: "test")
    assert response.is_a?(Array)
    assert response.size >= 1
  end

  def test_read_project_finds_by_name
    project = Project.find(1)

    response = @provider.read_project(project_name: project.name)
    assert_equal project.id, response[:id]
    assert_equal project.name, response[:name]
  end

  def test_read_project_finds_by_identifier
    project = Project.find(1)

    response = @provider.read_project(project_identifier: project.identifier)
    assert_equal project.id, response[:id]
    assert_equal project.identifier, response[:identifier]
  end

  def test_read_project_not_found_by_name
    assert_raises(RuntimeError, "Project not found") do
      @provider.read_project(project_name: "nonexistent_project")
    end
  end

  def test_read_project_not_found_by_identifier
    assert_raises(RuntimeError, "Project not found") do
      @provider.read_project(project_identifier: "nonexistent_identifier")
    end
  end

  def test_list_project_activities_with_author
    project = Project.find(1)
    author = User.find(1)

    response = @provider.list_project_activities(project_id: project.id, author_id: author.id)

    assert_equal "success", response.status
    assert response.value.key?(:activities)
  end

  def test_list_project_activities_with_limit
    project = Project.find(1)

    response = @provider.list_project_activities(project_id: project.id, limit: 5)

    assert_equal "success", response.status
    activities = response.value[:activities]
    assert activities.size <= 5
  end

  def test_project_enabled_modules_structure
    project = Project.find(1)

    response = @provider.project_enabled_modules(project_id: project.id)

    assert_equal project.id, response[:project_id]
    assert response[:enabled_modules].is_a?(Array)

    if response[:enabled_modules].any?
      module_info = response[:enabled_modules].first
      assert module_info.key?(:name)
    end
  end

  def test_get_metrics_includes_new_priority_a_metrics
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)

    assert metrics.key?(:update_frequency_metrics)
    assert metrics.key?(:estimation_accuracy_metrics)
    assert metrics.key?(:attachment_metrics)
  end

  def test_get_metrics_update_frequency_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    update_metrics = metrics[:update_frequency_metrics]

    assert update_metrics.key?(:average_updates_per_ticket)
    assert update_metrics.key?(:total_updates)
    assert update_metrics.key?(:update_recency_distribution)
    assert update_metrics.key?(:actively_updated_tickets)
    assert update_metrics.key?(:active_update_ratio)

    recency_dist = update_metrics[:update_recency_distribution]
    assert recency_dist.key?(:within_1_week)
    assert recency_dist.key?(:within_1_month)
    assert recency_dist.key?(:over_1_month)

    assert update_metrics[:average_updates_per_ticket].is_a?(Numeric)
    assert update_metrics[:total_updates].is_a?(Integer)
    assert update_metrics[:actively_updated_tickets].is_a?(Integer)
    assert update_metrics[:active_update_ratio].is_a?(Numeric)
  end

  def test_get_metrics_estimation_accuracy_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    accuracy_metrics = metrics[:estimation_accuracy_metrics]

    assert accuracy_metrics.key?(:accuracy_data_available)

    if accuracy_metrics[:accuracy_data_available]
      assert accuracy_metrics.key?(:average_accuracy_percentage)
      assert accuracy_metrics.key?(:estimation_ratios)
      assert accuracy_metrics.key?(:accuracy_by_tracker)
      assert accuracy_metrics.key?(:accuracy_by_assignee)
      assert accuracy_metrics.key?(:total_analyzed_issues)

      estimation_ratios = accuracy_metrics[:estimation_ratios]
      assert estimation_ratios.key?(:overestimated_count)
      assert estimation_ratios.key?(:underestimated_count)
      assert estimation_ratios.key?(:accurate_count)
      assert estimation_ratios.key?(:overestimated_ratio)
      assert estimation_ratios.key?(:underestimated_ratio)
      assert estimation_ratios.key?(:accurate_ratio)

      assert accuracy_metrics[:average_accuracy_percentage].is_a?(Numeric)
      assert accuracy_metrics[:total_analyzed_issues].is_a?(Integer)
    else
      assert_equal false, accuracy_metrics[:accuracy_data_available]
    end
  end

  def test_get_metrics_attachment_metrics_structure
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    attachment_metrics = metrics[:attachment_metrics]

    assert attachment_metrics.key?(:attachments_available)

    if attachment_metrics[:attachments_available]
      assert attachment_metrics.key?(:document_attachment_rate)
      assert attachment_metrics.key?(:total_attachments)
      assert attachment_metrics.key?(:average_attachments_per_ticket)
      assert attachment_metrics.key?(:average_attachments_per_ticket_with_attachments)
      assert attachment_metrics.key?(:file_type_distribution)
      assert attachment_metrics.key?(:file_size_statistics)

      file_size_stats = attachment_metrics[:file_size_statistics]
      assert file_size_stats.key?(:total_size_mb)
      assert file_size_stats.key?(:average_size_kb)
      assert file_size_stats.key?(:large_files_count)
      assert file_size_stats.key?(:large_files_ratio)

      assert attachment_metrics[:document_attachment_rate].is_a?(Numeric)
      assert attachment_metrics[:total_attachments].is_a?(Integer)
      assert attachment_metrics[:average_attachments_per_ticket].is_a?(Numeric)
      assert attachment_metrics[:file_type_distribution].is_a?(Hash)
    else
      assert_equal false, attachment_metrics[:attachments_available]
    end
  end

  def test_get_metrics_update_frequency_with_test_data
    project = Project.find(1)
    issue = project.issues.first

    original_journal_count = issue.journals.count

    journal1 = Journal.new(
      journalized: issue,
      user: User.find(1),
      notes: "Test update 1",
      created_on: 5.days.ago,
    )
    journal1.save!

    journal2 = Journal.new(
      journalized: issue,
      user: User.find(1),
      notes: "Test update 2",
      created_on: 2.days.ago,
    )
    journal2.save!

    issue.reload

    metrics = @provider.get_metrics(project_id: project.id)
    update_metrics = metrics[:update_frequency_metrics]

    assert update_metrics[:total_updates] >= original_journal_count + 2
    assert update_metrics[:average_updates_per_ticket] > 0
    assert update_metrics[:actively_updated_tickets] >= 1

    journal1.destroy
    journal2.destroy
  end

  def test_get_metrics_estimation_accuracy_with_test_data
    project = Project.find(1)
    issue = project.issues.first

    issue.update!(estimated_hours: 10.0)

    time_entry = TimeEntry.new(
      project: project,
      issue: issue,
      user: User.find(1),
      activity: TimeEntryActivity.first,
      hours: 12.0,
      spent_on: Date.current,
    )
    time_entry.save!

    metrics = @provider.get_metrics(project_id: project.id)
    accuracy_metrics = metrics[:estimation_accuracy_metrics]

    if accuracy_metrics[:accuracy_data_available]
      assert accuracy_metrics[:total_analyzed_issues] >= 1
      assert accuracy_metrics[:average_accuracy_percentage] > 0
      assert accuracy_metrics[:estimation_ratios][:underestimated_count] >= 1
    end

    time_entry.destroy
    issue.update!(estimated_hours: nil)
  end

  def test_get_metrics_attachment_with_test_data
    project = Project.find(1)
    issue = project.issues.first

    attachment = Attachment.new(
      container: issue,
      file: StringIO.new("test content"),
      filename: "test_document.pdf",
      author: User.find(1),
      filesize: 5000,
      content_type: "application/pdf",
    )
    attachment.save!

    metrics = @provider.get_metrics(project_id: project.id)
    attachment_metrics = metrics[:attachment_metrics]

    if attachment_metrics[:attachments_available]
      assert attachment_metrics[:total_attachments] >= 1
      assert attachment_metrics[:document_attachment_rate] > 0
      assert attachment_metrics[:file_type_distribution]["PDF"] >= 1 if attachment_metrics[:file_type_distribution]["PDF"]
      assert attachment_metrics[:file_size_statistics][:total_size_mb] > 0
    end

    attachment.destroy
  end

  def test_get_metrics_update_frequency_edge_cases
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    update_metrics = metrics[:update_frequency_metrics]

    assert update_metrics[:average_updates_per_ticket] >= 0
    assert update_metrics[:total_updates] >= 0
    assert update_metrics[:active_update_ratio] >= 0
    assert update_metrics[:active_update_ratio] <= 100
  end

  def test_get_metrics_estimation_accuracy_no_data
    project = Project.find(1)

    project.issues.each do |issue|
      issue.update!(estimated_hours: nil)
      issue.time_entries.destroy_all
    end

    metrics = @provider.get_metrics(project_id: project.id)
    accuracy_metrics = metrics[:estimation_accuracy_metrics]

    assert_equal false, accuracy_metrics[:accuracy_data_available]
  end

  def test_get_metrics_attachment_no_data
    project = Project.find(1)

    project.issues.each do |issue|
      issue.attachments.destroy_all
    end

    metrics = @provider.get_metrics(project_id: project.id)
    attachment_metrics = metrics[:attachment_metrics]

    assert_equal false, attachment_metrics[:attachments_available]
  end

  def test_calculate_repository_metrics_is_public
    project = Project.find(1)
    # Should be able to call without send
    metrics = @provider.calculate_repository_metrics(project)
    assert metrics[:repository_available]
  end

  def test_get_metrics_with_version_excludes_repository_metrics
    project = Project.find(1)
    version = project.versions.first

    metrics = @provider.get_metrics(project_id: project.id, version_id: version.id)

    # Repository metrics should be empty when version is specified
    assert_equal({}, metrics[:repository_metrics])
  end

  def test_get_metrics_without_version_includes_repository_metrics
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)

    # Repository metrics should be present when version is NOT specified
    assert metrics[:repository_metrics][:repository_available]
    assert metrics[:repository_metrics][:total_commits]
  end
end
