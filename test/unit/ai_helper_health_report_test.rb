require_relative "../test_helper"

class AiHelperHealthReportTest < ActiveSupport::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :issues, :versions

  def setup
    @project = Project.find(1)
    @user = User.find(2)
    @version = Version.find(1)

    # Enable AI Helper module for the project
    @project.enabled_module_names = @project.enabled_module_names + ["ai_helper"]
    @project.save!
  end

  context "AiHelperHealthReport" do
    should "belong to project" do
      report = AiHelperHealthReport.new
      assert_respond_to report, :project
    end

    should "belong to user" do
      report = AiHelperHealthReport.new
      assert_respond_to report, :user
    end

    should "validate presence of project_id" do
      report = AiHelperHealthReport.new(
        user_id: @user.id,
        health_report: "Test report",
      )
      assert_not report.valid?
      assert report.errors[:project_id].present?
    end

    should "validate presence of user_id" do
      report = AiHelperHealthReport.new(
        project_id: @project.id,
        health_report: "Test report",
      )
      assert_not report.valid?
      assert report.errors[:user_id].present?
    end

    should "validate presence of health_report" do
      report = AiHelperHealthReport.new(
        project_id: @project.id,
        user_id: @user.id,
      )
      assert_not report.valid?
      assert report.errors[:health_report].present?
    end

    should "create a valid health report" do
      report = AiHelperHealthReport.new(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Test report",
      )
      assert report.valid?
      assert report.save
    end

    should "store and retrieve metrics as hash" do
      report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Test report",
      )

      metrics = { "total_issues" => 10, "closed_issues" => 5 }
      report.metrics_hash = metrics
      report.save!

      report.reload
      # metrics_hash returns symbolized keys
      assert_equal({ total_issues: 10, closed_issues: 5 }, report.metrics_hash)
    end

    should "return empty hash when metrics is blank" do
      report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Test report",
      )
      assert_equal({}, report.metrics_hash)
    end

    should "return sorted reports" do
      AiHelperHealthReport.destroy_all

      older_report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Older report",
        created_at: 2.days.ago,
      )

      newer_report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Newer report",
        created_at: 1.day.ago,
      )

      reports = AiHelperHealthReport.sorted
      assert_equal 2, reports.count
      assert_equal newer_report.id, reports.first.id
      assert_equal older_report.id, reports.last.id
    end

    should "return reports for specific project" do
      AiHelperHealthReport.destroy_all
      project2 = Project.find(2)

      report1 = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Report for project 1",
      )

      report2 = AiHelperHealthReport.create!(
        project_id: project2.id,
        user_id: @user.id,
        health_report: "Report for project 2",
      )

      reports = AiHelperHealthReport.for_project(@project.id)
      assert_equal 1, reports.count
      assert_equal report1.id, reports.first.id
    end

    should "return reports by specific user" do
      AiHelperHealthReport.destroy_all
      user2 = User.find(3)

      report1 = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Report by user 1",
      )

      report2 = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: user2.id,
        health_report: "Report by user 2",
      )

      reports = AiHelperHealthReport.by_user(@user.id)
      assert_equal 1, reports.count
      assert_equal report1.id, reports.first.id
    end

    should "return recent reports with limit" do
      15.times do |i|
        AiHelperHealthReport.create!(
          project_id: @project.id,
          user_id: @user.id,
          health_report: "Report #{i}",
          created_at: i.days.ago,
        )
      end

      reports = AiHelperHealthReport.recent(5)
      assert_equal 5, reports.count
    end

    should "check if report is visible to user" do
      report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Test report",
      )

      User.current = @user
      # Add view_ai_helper permission
      role = Role.find(1)
      role.add_permission! :view_ai_helper

      # Ensure user has the role for this project
      member = Member.find_by(project_id: @project.id, user_id: @user.id)
      if member.nil?
        member = Member.new(project_id: @project.id, user_id: @user.id)
        member.role_ids = [role.id]
        member.save!
      else
        member.role_ids = [role.id]
        member.save!
      end

      assert report.visible?(@user)
    end

    should "check if report is deletable by owner" do
      report = AiHelperHealthReport.create!(
        project_id: @project.id,
        user_id: @user.id,
        health_report: "Test report",
      )

      User.current = @user
      # Add view_ai_helper permission
      role = Role.find(1)
      role.add_permission! :view_ai_helper

      # Ensure user has the role for this project
      member = Member.find_by(project_id: @project.id, user_id: @user.id)
      if member.nil?
        member = Member.new(project_id: @project.id, user_id: @user.id)
        member.role_ids = [role.id]
        member.save!
      else
        member.role_ids = [role.id]
        member.save!
      end

      assert report.deletable?(@user)
    end

    should "check if reports are comparable" do
      report1 = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report 1",
        metrics: {}.to_json,
      )

      report2 = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report 2",
        metrics: {}.to_json,
      )

      assert report1.comparable_with?(report2)
      assert report2.comparable_with?(report1)
    end

    should "not be comparable with same report" do
      report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report 1",
        metrics: {}.to_json,
      )

      assert_not report.comparable_with?(report)
    end

    should "not be comparable with reports from different projects" do
      project2 = Project.find(2)

      report1 = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report 1",
        metrics: {}.to_json,
      )

      report2 = AiHelperHealthReport.create!(
        project: project2,
        user: @user,
        health_report: "Report 2",
        metrics: {}.to_json,
      )

      assert_not report1.comparable_with?(report2)
    end

    should "not be comparable with non-health-report objects" do
      report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report 1",
        metrics: {}.to_json,
      )

      assert_not report.comparable_with?("not a report")
      assert_not report.comparable_with?(nil)
      assert_not report.comparable_with?(@project)
    end

    should "return summary info" do
      metrics = {
        issue_statistics: {
          total_issues: 50,
        },
      }

      report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Test report",
        metrics: metrics.to_json,
      )

      summary = report.summary_info
      assert_equal report.id, summary[:id]
      assert_equal report.created_at, summary[:created_at]
      assert_equal @user.name, summary[:user_name]
      assert_equal 50, summary[:total_issues]
    end

    should "return summary info with zero issues when metrics missing" do
      report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Test report",
      )

      summary = report.summary_info
      assert_equal 0, summary[:total_issues]
    end
  end
end
