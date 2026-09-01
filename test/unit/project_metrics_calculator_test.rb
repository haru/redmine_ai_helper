require File.expand_path("../../test_helper", __FILE__)
require "redmine_ai_helper/project_metrics_calculator"

class RedmineAiHelper::ProjectMetricsCalculatorTest < ActiveSupport::TestCase
  fixtures :projects, :projects_trackers, :trackers, :users, :repositories, :changesets, :changes, :issues, :issue_statuses, :enumerations, :issue_categories, :trackers

  def setup
    @calculator = RedmineAiHelper::ProjectMetricsCalculator.new
  end

  def test_calculate_repository_metrics_is_public
    project = Project.find(1)
    # Should be able to call without send
    metrics = @calculator.calculate_repository_metrics(project)

    assert metrics[:repository_available]
  end

  def test_calculate_repository_metrics_with_commits
    project = Project.find(1)

    metrics = @calculator.calculate_repository_metrics(project)

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

    metrics = @calculator.calculate_repository_metrics(project, start_date: start_date, end_date: end_date)

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

    metrics = @calculator.calculate_repository_metrics(project)

    assert_equal true, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits]
    assert_equal({}, metrics[:commit_frequency])

    repo.destroy
  end

  def test_calculate_repository_metrics_without_repository
    project_without_repo = Project.find(3)

    metrics = @calculator.calculate_repository_metrics(project_without_repo)

    assert_equal false, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits].to_i
  end

  def test_calculate_repository_metrics_handles_error
    project = Project.find(1)
    Changeset.expects(:joins).with(:repository).raises(StandardError.new("db failure"))

    metrics = @calculator.calculate_repository_metrics(project)

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

    metrics = @calculator.calculate_repository_metrics(project)

    assert_equal true, metrics[:repository_available]
    assert_equal 0, metrics[:total_commits]
  end

  def test_calculate_commit_frequency
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(100).to_a
    start_date = 30.days.ago.to_date
    end_date = Date.current

    frequency = @calculator.send(:calculate_commit_frequency, changesets, start_date, end_date)

    assert_operator frequency[:total_commits], :>=, 0
    assert_operator frequency[:daily_average], :>=, 0
    assert_operator frequency[:weekly_average], :>=, 0
    assert_operator frequency[:monthly_average], :>=, 0
  end

  def test_calculate_commit_timeline
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(50).to_a

    timeline = @calculator.send(:calculate_commit_timeline, changesets, nil, nil)

    assert timeline.key?(:by_date)
    assert timeline.key?(:by_week)
    assert timeline.key?(:by_weekday)
    assert timeline.key?(:by_hour)
  end

  def test_calculate_commit_size_metrics
    project = Project.find(1)
    changesets = project.repositories.first.changesets.limit(50).to_a

    metrics = @calculator.send(:calculate_commit_size_metrics, changesets)

    if metrics.empty?
      assert_equal({}, metrics)
    else
      assert metrics.key?(:average_comment_length)
      assert metrics.key?(:median_comment_length)
      assert metrics.key?(:empty_comments_count)
    end
  end
end
