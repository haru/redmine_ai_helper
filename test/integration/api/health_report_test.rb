require_relative "../../test_helper"

class ApiHealthReportTest < Redmine::IntegrationTest
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules, :trackers

  def setup
    # Enable REST API
    Setting.rest_api_enabled = '1'

    @project = Project.find(1)

    # Create role with AI Helper permission
    @role = Role.find_or_create_by(name: 'AI Helper Test Role') do |role|
      role.permissions = [:view_ai_helper, :view_issues, :view_project]
      role.issues_visibility = 'all'
    end
    @role.add_permission!(:view_ai_helper) unless @role.permissions.include?(:view_ai_helper)
    @role.save!

    # Create user with API key
    @user = User.find(2)  # jsmith from fixtures
    @user.generate_api_key if @user.api_key.blank?

    # Remove existing memberships and add with our role
    @project.members.where(user_id: @user.id).destroy_all
    Member.create!(user: @user, project: @project, roles: [@role])

    # Enable AI Helper module
    unless @project.module_enabled?('ai_helper')
      EnabledModule.create!(project_id: @project.id, name: "ai_helper")
      @project.reload
    end
  end

  test "POST /projects/:id/ai_helper/health_report.json with API key should create health report" do
    # Mock LLM to avoid actual API calls
    llm_mock = mock("RedmineAiHelper::Llm")
    llm_mock.stubs(:project_health_report).returns("# Health Report")
    RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

    # Create a pre-existing report
    AiHelperHealthReport.create!(
      project: @project,
      user: @user,
      health_report: "# Health Report",
      metrics: {}.to_json
    )

    post "/projects/#{@project.identifier}/ai_helper/health_report.json",
         headers: { 'X-Redmine-API-Key' => @user.api_key }

    assert_response :success, "Expected 200 but got #{response.status}. Body: #{response.body}"
    json = JSON.parse(response.body)
    assert json.key?('id')
    assert_equal @project.id, json['project_id']
    assert json.key?('health_report')
    assert json.key?('created_at')
  end

  test "POST /projects/:id/ai_helper/health_report.json without API key should return 401" do
    post "/projects/#{@project.identifier}/ai_helper/health_report.json"

    assert_response :unauthorized
  end
end
