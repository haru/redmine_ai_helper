require_relative "../test_helper"

class ProjectHealthPartialTest < ActionView::TestCase
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules

  setup do
    @project = projects(:projects_001)
    @project.enable_module!(:ai_helper)
    @user = users(:users_001)

    User.current = @user
    Rails.cache.clear
    AiHelperHealthReport.delete_all
  end

  teardown do
    User.current = nil
    Rails.cache.clear
  end

  should "render the latest stored health report when cache is empty" do
    report = AiHelperHealthReport.create!(
      project: @project,
      user: @user,
      health_report: "Stored health report content"
    )

    html = render(
      partial: "ai_helper/project/health_report",
      locals: { project: @project }
    )

    assert_includes html, "Stored health report content"
    assert_includes html, l(:field_created_on)
    assert_includes html, format_time(report.created_at)
    assert_includes html, ai_helper_project_health_metadata_path(@project)
    assert_includes html, 'meta name="ai-helper-project-health-created-label"'
  end
end
