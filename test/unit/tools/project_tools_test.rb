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
    [ project1, project2 ].each_with_index do |project, index|
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

    response = @provider.project_members(project_ids: [ project.id ])

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

    response = @provider.project_members(project_ids: [ project1.id, project2.id ])

    assert_equal 2, response[:projects].size
    assert(response[:projects].all? { |p| p.key?(:members) })
  end

  def test_project_members_with_invalid_project_id
    response = @provider.project_members(project_ids: [ 999 ])

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
    response = @provider.list_project_activities(project_id: 999)

    assert_equal "error", response.status
    assert_match(/not found/i, response.error)
  end

  def test_list_project_activities_with_invalid_author_id
    project = Project.find(1)

    assert_raises(ActiveRecord::RecordNotFound) do
      @provider.list_project_activities(project_id: project.id, author_id: 999)
    end
  end

  def test_list_project_activities_without_project_id_spans_multiple_projects
    project1 = Project.find(1)
    project2 = Project.find(2)
    EnabledModule.create!(project_id: project2.id, name: "ai_helper")

    issue1 = Issue.create!(
      project: project1, tracker: Tracker.find(1), subject: "Cross Project Activity 1",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )
    issue2 = Issue.create!(
      project: project2, tracker: Tracker.find(1), subject: "Cross Project Activity 2",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    titles = response.value[:activities].map { |a| a[:event_title] }
    assert(titles.any? { |t| t.include?("Cross Project Activity 1") })
    assert(titles.any? { |t| t.include?("Cross Project Activity 2") })

    datetimes = response.value[:activities].map { |a| a[:event_datetime] }
    assert_equal datetimes, datetimes.sort.reverse
  ensure
    issue1&.destroy
    issue2&.destroy
  end

  def test_list_project_activities_without_project_id_applies_limit_after_project_filter
    project1 = Project.find(1)
    excluded_project = Project.find(3) # ai_helper module not enabled
    tracker = Tracker.find(1)
    excluded_project.trackers << tracker unless excluded_project.trackers.include?(tracker)

    accessible_issue_a = Issue.create!(
      project: project1, tracker: tracker, subject: "Limit Order Accessible A",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )
    accessible_issue_b = Issue.create!(
      project: project1, tracker: tracker, subject: "Limit Order Accessible B",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )
    # Created after the accessible issues, so they would sort ahead of them by
    # event_datetime if the project filter were (incorrectly) applied after the limit
    # instead of before it.
    excluded_issue_a = Issue.create!(
      project: excluded_project, tracker: tracker, subject: "Limit Order Excluded A",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )
    excluded_issue_b = Issue.create!(
      project: excluded_project, tracker: tracker, subject: "Limit Order Excluded B",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: nil, limit: 2)

    assert_equal "success", response.status
    titles = response.value[:activities].map { |a| a[:event_title] }
    assert_equal 2, titles.size
    assert(titles.any? { |t| t.include?("Limit Order Accessible A") })
    assert(titles.any? { |t| t.include?("Limit Order Accessible B") })
  ensure
    accessible_issue_a&.destroy
    accessible_issue_b&.destroy
    excluded_issue_a&.destroy
    excluded_issue_b&.destroy
  end

  def test_list_project_activities_without_project_id_respects_author_id_filter
    project1 = Project.find(1)
    project2 = Project.find(2)
    EnabledModule.create!(project_id: project2.id, name: "ai_helper")
    author = User.find(2)
    other_author = User.find(1)

    matching_issue = Issue.create!(
      project: project2, tracker: Tracker.find(1), subject: "Cross Project Author Match",
      author: author, status: IssueStatus.first, priority: IssuePriority.first
    )
    other_issue = Issue.create!(
      project: project1, tracker: Tracker.find(1), subject: "Cross Project Author Mismatch",
      author: other_author, status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: nil, author_id: author.id)

    assert_equal "success", response.status
    titles = response.value[:activities].map { |a| a[:event_title] }
    assert(titles.any? { |t| t.include?("Cross Project Author Match") })
    assert_not(titles.any? { |t| t.include?("Cross Project Author Mismatch") })
  ensure
    matching_issue&.destroy
    other_issue&.destroy
  end

  def test_list_project_activities_without_project_id_excludes_projects_without_permission
    previous_user = User.current
    User.current = User.find(2) # jsmith, a member of project 1 but not of the private_project created below
    Role.find(1).add_permission!(:view_ai_helper)

    private_project = Project.create!(
      name: "Private No Access #{Time.now.to_i}#{rand(10000)}",
      identifier: "private-no-access-#{Time.now.to_i}#{rand(10000)}",
      is_public: false
    )
    tracker = Tracker.find(1)
    private_project.trackers << tracker unless private_project.trackers.include?(tracker)
    EnabledModule.create!(project_id: private_project.id, name: "ai_helper")
    hidden_issue = Issue.create!(
      project: private_project, tracker: tracker, subject: "Hidden No Permission Activity",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    titles = response.value[:activities].map { |a| a[:event_title] }
    assert_not(titles.any? { |t| t.include?("Hidden No Permission Activity") })
  ensure
    User.current = previous_user
    hidden_issue&.destroy
    private_project&.destroy
  end

  def test_list_project_activities_without_project_id_excludes_ai_helper_disabled_project
    project_without_ai_helper = Project.find(3) # eCookbook Subproject 1: ai_helper module not enabled
    tracker = Tracker.find(1)
    project_without_ai_helper.trackers << tracker unless project_without_ai_helper.trackers.include?(tracker)
    issue = Issue.create!(
      project: project_without_ai_helper, tracker: tracker, subject: "No AI Helper Module Activity",
      author: User.find(1), status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    titles = response.value[:activities].map { |a| a[:event_title] }
    assert_not(titles.any? { |t| t.include?("No AI Helper Module Activity") })
  ensure
    issue&.destroy
  end

  def test_list_project_activities_without_project_id_and_no_accessible_projects_returns_empty
    EnabledModule.where(project_id: 1, name: "ai_helper").destroy_all

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    assert_equal [], response.value[:activities]
  end

  def test_list_project_activities_includes_user_id
    project = Project.find(1)
    issue = Issue.create!(
      project: project, tracker: Tracker.find(1), subject: "User Id Field Activity",
      author: User.find(2), status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: project.id)

    assert_equal "success", response.status
    activity = response.value[:activities].find { |a| a[:event_title].to_s.include?("User Id Field Activity") }

    assert_not_nil activity
    assert_equal issue.author.id, activity[:user_id]
  ensure
    issue&.destroy
  end

  def test_list_project_activities_with_author_id_matches_user_id
    project = Project.find(1)
    author = User.find(2)
    issue = Issue.create!(
      project: project, tracker: Tracker.find(1), subject: "Author Filter Activity",
      author: author, status: IssueStatus.first, priority: IssuePriority.first
    )

    response = @provider.list_project_activities(project_id: project.id, author_id: author.id)

    assert_equal "success", response.status
    activities = response.value[:activities]

    assert(activities.any?)
    assert(activities.all? { |a| a[:user_id] == author.id })
  ensure
    issue&.destroy
  end

  def test_list_project_activities_user_id_is_nil_when_author_unknown
    project = Project.find(1)
    document = Document.create!(project: project, title: "Doc Without Attachment Activity", category: DocumentCategory.first)

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    activity = response.value[:activities].find { |a| a[:event_title].to_s.include?("Doc Without Attachment Activity") }

    assert_not_nil activity
    assert_nil activity[:user_id]
  ensure
    document&.destroy
  end

  def test_list_project_activities_user_id_is_nil_for_changeset_with_unmapped_committer
    repository = Repository.find(10) # belongs to project 1
    changeset = Changeset.create!(
      repository: repository,
      revision: "unmapped-committer-#{Time.now.to_i}#{rand(10000)}",
      committer: "Unmapped Committer <unmapped@example.com>",
      committed_on: Time.current,
      commit_date: Time.zone.today,
      comments: "Changeset Without Mapped User Activity",
      user: nil
    )

    response = @provider.list_project_activities(project_id: nil)

    assert_equal "success", response.status
    activity = response.value[:activities].find { |a| a[:event_title].to_s.include?("Changeset Without Mapped User Activity") }

    assert_not_nil activity
    assert_nil activity[:user_id]
  ensure
    changeset&.destroy
  end

  def test_list_project_activities_description_mentions_optional_project_id_and_user_id
    schema = RedmineAiHelper::Tools::ProjectTools.function_schemas.to_openai_format.find do |f|
      f[:function][:name].end_with?("__list_project_activities")
    end

    assert_match(/omit/i, schema[:function][:description])
    assert_match(/user_id/i, schema[:function][:description])
    assert_match(/omit/i, schema[:function][:parameters][:properties][:project_id][:description])
  end

  def test_list_project_activities_limit_description_states_the_actual_default
    schema = RedmineAiHelper::Tools::ProjectTools.function_schemas.to_openai_format.find do |f|
      f[:function][:name].end_with?("__list_project_activities")
    end
    limit_description = schema[:function][:parameters][:properties][:limit][:description]

    assert_match(/100/, limit_description)
    assert_no_match(/all activities/i, limit_description)
  end

  def test_accessible_projects_excludes_inaccessible_projects
    accessible_ids = @provider.accessible_projects.map(&:id)

    assert_includes accessible_ids, 1 # ai_helper enabled and visible
    assert_not_includes accessible_ids, 3 # ai_helper module not enabled
  end

  def test_event_project_id_prefers_the_foreign_key_over_the_association
    project = Project.find(1)
    issue = Issue.create!(
      project: project, tracker: Tracker.find(1), subject: "Event Project Id Activity",
      author: User.find(2), status: IssueStatus.first, priority: IssuePriority.first
    )

    assert_equal project.id, @provider.event_project_id(issue)
  ensure
    issue&.destroy
  end

  def test_event_project_id_falls_back_to_the_association
    event = Struct.new(:project).new(Project.find(1))

    assert_equal 1, @provider.event_project_id(event)
  end

  def test_event_project_id_is_nil_without_a_project
    event = Struct.new(:project).new(nil)

    assert_nil @provider.event_project_id(event)
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

    response = @provider.project_members(project_ids: [ project.id ])
    project_data = response[:projects].first

    assert project_data.key?(:members)
    assert_kind_of Array, project_data[:members]
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
    assert_kind_of Array, response[:subprojects]
  end

  def test_read_project_includes_custom_fields
    project = Project.find(1)
    custom_field = ProjectCustomField.create!(name: "Contract Type", field_format: "string", is_for_all: true)
    project.custom_field_values = { custom_field.id => "Enterprise" }
    project.save!

    response = @provider.read_project(project_id: project.id)

    assert response.key?(:custom_fields)
    field_data = response[:custom_fields].find { |f| f[:id] == custom_field.id }
    assert_equal custom_field.name, field_data[:name]
    assert_equal "Enterprise", field_data[:value]

    custom_field.destroy
  end

  def test_project_members_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    response = @provider.project_members(project_ids: [ project.id ])
    # When user has no permission, accessible projects are filtered out, resulting in empty list
    assert_equal [], response[:projects]
  end

  def test_project_enabled_modules_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    result = @provider.project_enabled_modules(project_id: project.id)

    assert_kind_of RedmineAiHelper::ToolResponse, result
    assert_equal "error", result.status
    assert_equal "You don't have permission to view this project", result.error
  end

  def test_list_project_activities_permission_check
    project = Project.find(1)
    User.current = User.find(6) # User without permission

    result = @provider.list_project_activities(project_id: project.id)

    assert_kind_of RedmineAiHelper::ToolResponse, result
    assert_equal "error", result.status
    assert_equal "You don't have permission to view this project", result.error
  end

  context "list_project_activities project and hours fields" do
    setup do
      @project = Project.find(1)
      @user = User.find(1)
    end

    should "include project with id and name in every activity" do
      Issue.create!(
        project: @project, tracker: Tracker.find(1), subject: "Project Field Test",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      response = @provider.list_project_activities(project_id: @project.id)
      activities = response.value[:activities]

      assert(activities.all? { |a| a.key?(:project) && a[:project]&.key?(:id) && a[:project].key?(:name) },
             "Every activity must include a project hash with id and name")
    ensure
      Issue.where(subject: "Project Field Test")&.destroy_all
    end

    should "include hours for time_entries activities and nil for others" do
      time_entry = TimeEntry.create!(
        project: @project, user: @user, activity: TimeEntryActivity.first,
        hours: 3.5, spent_on: Date.current, comments: "Hours Field Test"
      )

      response = @provider.list_project_activities(project_id: @project.id, event_types: [ "time_entries" ])
      te_activities = response.value[:activities]

      assert(te_activities.any?, "Expected at least one time_entry activity")
      assert(te_activities.all? { |a| a[:hours].is_a?(Numeric) && a[:hours] > 0 },
             "time_entries activities must have a positive numeric hours value")

      Issue.create!(
        project: @project, tracker: Tracker.find(1), subject: "Non Time Entry Hours Test",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )
      issue_response = @provider.list_project_activities(project_id: @project.id, event_types: [ "issues" ])
      non_te = issue_response.value[:activities]

      assert(non_te.all? { |a| a[:hours].nil? },
             "Non-time_entries activities must have nil hours")
    ensure
      time_entry&.destroy
      Issue.where(subject: "Non Time Entry Hours Test")&.destroy_all
    end

    should "not change event_title for time_entries activities" do
      time_entry = TimeEntry.create!(
        project: @project, user: @user, activity: TimeEntryActivity.first,
        hours: 2.5, spent_on: Date.current, comments: "Title Preserve Test"
      )

      response = @provider.list_project_activities(project_id: @project.id, event_types: [ "time_entries" ])
      activities = response.value[:activities]

      if activities.any?
        activity = activities.first
        assert_match(/\d/, activity[:event_title].to_s,
                     "event_title should contain a numeric hours string")
      else
        skip "No time_entries activities returned (time_entries may not be an active event type)"
      end
    ensure
      time_entry&.destroy
    end
  end

  context "list_project_activities event_types filter" do
    setup do
      @project = Project.find(1)
      @user = User.find(1)
    end

    should "return only activities of the specified single event type" do
      response = @provider.list_project_activities(project_id: @project.id, event_types: [ "issues" ])

      assert_equal "success", response.status
      activities = response.value[:activities]
      assert(activities.all? { |a| a[:event_type].start_with?("issue") },
             "Expected all activities to start with 'issue', got: #{activities.map { |a| a[:event_type] }.uniq.inspect}")
    end

    should "return activities matching any of the specified event types (OR condition)" do
      response = @provider.list_project_activities(project_id: @project.id, event_types: [ "issues", "news" ])

      assert_equal "success", response.status
      activities = response.value[:activities]
      assert(activities.all? { |a| a[:event_type].start_with?("issue") || a[:event_type] == "news" },
             "Expected only issues or news, got: #{activities.map { |a| a[:event_type] }.uniq.inspect}")
    end

    should "return empty activities without error when event_types contains non-existent types" do
      response = @provider.list_project_activities(project_id: @project.id, event_types: [ "nonexistent_type" ])

      assert_equal "success", response.status
      assert_equal [], response.value[:activities]
    end

    should "return all activity types when event_types is omitted (non-regression)" do
      Issue.create!(
        project: @project, tracker: Tracker.find(1), subject: "Event Types Omitted Test",
        author: @user, status: IssueStatus.first, priority: IssuePriority.first
      )

      response = @provider.list_project_activities(project_id: @project.id)

      assert_equal "success", response.status
      activities = response.value[:activities]
      assert(activities.any?, "Expected at least one activity when event_types is omitted")
    ensure
      Issue.where(subject: "Event Types Omitted Test")&.destroy_all
    end
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
      end_date: end_date
    )

    assert_equal Date.parse(start_date), metrics[:period][:start_date]
    assert_equal Date.parse(end_date), metrics[:period][:end_date]
  end

  def test_calculate_repository_metrics_with_commits
    project = Project.find(1)

    metrics = @provider.send(:calculate_repository_metrics, project)

    assert_equal true, metrics[:repository_available]
    assert_operator metrics[:total_commits], :>=, 0
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
      assert_operator metrics[:commit_frequency][:period_days], :<=, 8
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

    assert_operator frequency[:total_commits], :>=, 0
    assert_operator frequency[:daily_average], :>=, 0
    assert_operator frequency[:weekly_average], :>=, 0
    assert_operator frequency[:monthly_average], :>=, 0
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

  def test_progress_metrics_closed_issue_with_zero_done_ratio_not_counted_as_not_started
    project = Project.find(1)
    closed_status = IssueStatus.find_by!(is_closed: true)

    # Create a closed issue with done_ratio = 0
    closed_issue = Issue.new(
      project: project,
      tracker: project.trackers.first,
      author: User.find(1),
      subject: "Closed issue with zero progress",
      status: closed_status,
      done_ratio: 0
    )
    closed_issue.save!

    metrics = @provider.get_metrics(project_id: project.id)
    completion_dist = metrics[:progress_metrics][:completion_distribution]

    # The closed issue should not appear in not_started
    open_issues_with_zero_ratio = project.issues.reload.select { |i| !i.status.is_closed? && (i.done_ratio || 0) == 0 }

    assert_equal open_issues_with_zero_ratio.count, completion_dist[:not_started]
  end

  def test_progress_metrics_closed_issue_counted_as_completed
    project = Project.find(1)
    closed_status = IssueStatus.find_by!(is_closed: true)

    # Create a closed issue with done_ratio = 50 (not 100)
    closed_issue = Issue.new(
      project: project,
      tracker: project.trackers.first,
      author: User.find(1),
      subject: "Closed issue with partial progress",
      status: closed_status,
      done_ratio: 50
    )
    closed_issue.save!

    metrics = @provider.get_metrics(project_id: project.id)
    completion_dist = metrics[:progress_metrics][:completion_distribution]

    # The closed issue should appear in completed, not in_progress
    all_issues = project.issues.includes(:status).reload.to_a
    expected_completed = all_issues.select { |i| i.status.is_closed? || (i.done_ratio || 0) == 100 }.count

    assert_equal expected_completed, completion_dist[:completed]

    # in_progress should not include the closed issue
    expected_in_progress = all_issues.select { |i| !i.status.is_closed? && (r = (i.done_ratio || 0); r > 0 && r < 100) }.count

    assert_equal expected_in_progress, completion_dist[:in_progress]
  end

  def test_progress_metrics_average_completion_treats_closed_as_100
    project = Project.find(1)
    closed_status = IssueStatus.find_by!(is_closed: true)
    open_status = IssueStatus.find_by!(is_closed: false)

    # Remove existing issues to have a controlled set
    project.issues.destroy_all

    Issue.create!(
      project: project,
      tracker: project.trackers.first,
      author: User.find(1),
      subject: "Open issue 0%",
      status: open_status,
      done_ratio: 0
    )
    Issue.create!(
      project: project,
      tracker: project.trackers.first,
      author: User.find(1),
      subject: "Closed issue 0%",
      status: closed_status,
      done_ratio: 0
    )

    metrics = @provider.get_metrics(project_id: project.id)
    progress_metrics = metrics[:progress_metrics]

    # total_done_ratio = 0 (open) + 100 (closed) = 100, average = 100/2 = 50.0
    assert_in_delta(50.0, progress_metrics[:average_completion_percentage])
    # issues_with_progress: closed issue counts as having progress
    assert_equal 1, progress_metrics[:issues_with_progress]
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

    assert_kind_of Array, response
    assert_operator response.size, :>=, 1
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

    assert_operator activities.size, :<=, 5
  end

  def test_project_enabled_modules_structure
    project = Project.find(1)

    response = @provider.project_enabled_modules(project_id: project.id)

    assert_equal project.id, response[:project_id]
    assert_kind_of Array, response[:enabled_modules]

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

    assert_kind_of Numeric, update_metrics[:average_updates_per_ticket]
    assert_kind_of Integer, update_metrics[:total_updates]
    assert_kind_of Integer, update_metrics[:actively_updated_tickets]
    assert_kind_of Numeric, update_metrics[:active_update_ratio]
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

      assert_kind_of Numeric, accuracy_metrics[:average_accuracy_percentage]
      assert_kind_of Integer, accuracy_metrics[:total_analyzed_issues]
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

      assert_kind_of Numeric, attachment_metrics[:document_attachment_rate]
      assert_kind_of Integer, attachment_metrics[:total_attachments]
      assert_kind_of Numeric, attachment_metrics[:average_attachments_per_ticket]
      assert_kind_of Hash, attachment_metrics[:file_type_distribution]
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
      created_on: 5.days.ago
    )
    journal1.save!

    journal2 = Journal.new(
      journalized: issue,
      user: User.find(1),
      notes: "Test update 2",
      created_on: 2.days.ago
    )
    journal2.save!

    issue.reload

    metrics = @provider.get_metrics(project_id: project.id)
    update_metrics = metrics[:update_frequency_metrics]

    assert_operator update_metrics[:total_updates], :>=, original_journal_count + 2
    assert_operator update_metrics[:average_updates_per_ticket], :>, 0
    assert_operator update_metrics[:actively_updated_tickets], :>=, 1

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
      spent_on: Date.current
    )
    time_entry.save!

    metrics = @provider.get_metrics(project_id: project.id)
    accuracy_metrics = metrics[:estimation_accuracy_metrics]

    if accuracy_metrics[:accuracy_data_available]
      assert_operator accuracy_metrics[:total_analyzed_issues], :>=, 1
      assert_operator accuracy_metrics[:average_accuracy_percentage], :>, 0
      assert_operator accuracy_metrics[:estimation_ratios][:underestimated_count], :>=, 1
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
      content_type: "application/pdf"
    )
    attachment.save!

    metrics = @provider.get_metrics(project_id: project.id)
    attachment_metrics = metrics[:attachment_metrics]

    if attachment_metrics[:attachments_available]
      assert_operator attachment_metrics[:total_attachments], :>=, 1
      assert_operator attachment_metrics[:document_attachment_rate], :>, 0
      assert_operator attachment_metrics[:file_type_distribution]["PDF"], :>=, 1 if attachment_metrics[:file_type_distribution]["PDF"]

      assert_operator attachment_metrics[:file_size_statistics][:total_size_mb], :>, 0
    end

    attachment.destroy
  end

  def test_get_metrics_update_frequency_edge_cases
    project = Project.find(1)

    metrics = @provider.get_metrics(project_id: project.id)
    update_metrics = metrics[:update_frequency_metrics]

    assert_operator update_metrics[:average_updates_per_ticket], :>=, 0
    assert_operator update_metrics[:total_updates], :>=, 0
    assert_operator update_metrics[:active_update_ratio], :>=, 0
    assert_operator update_metrics[:active_update_ratio], :<=, 100
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
