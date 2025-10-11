require_relative '../test_helper'

class AiHelperDashboardControllerTest < ActionController::TestCase
  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  context "AiHelperDashboardController" do
    setup do
      @controller = AiHelperDashboardController.new
      @request = ActionController::TestRequest.create(@controller.class)
      @response = ActionDispatch::TestResponse.create
      @user = User.find(1)
      @project = Project.find(1)
      @request.session[:user_id] = @user.id

      # Enable AI Helper module for the project
      enabled_module = EnabledModule.new
      enabled_module.project_id = @project.id
      enabled_module.name = "ai_helper"
      enabled_module.save!
    end

    context "#index" do
      should "display dashboard overview tab" do
        get :index, params: { id: @project.id }
        assert_response :success
        assert_template :index
      end

      should "display dashboard with health report tab" do
        # Create some health reports
        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 1",
          created_at: 2.days.ago
        )
        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 2",
          created_at: 1.day.ago
        )

        get :index, params: { id: @project.id, tab: 'health_report' }
        assert_response :success
        assert_template :index
        assert_select '.ai-helper-health-report-history', 1
      end

      should "display paginated health reports in dashboard" do
        # Clean up existing reports
        AiHelperHealthReport.where(project: @project).destroy_all

        # Create 15 reports
        15.times do |i|
          AiHelperHealthReport.create!(
            project: @project,
            user: @user,
            health_report: "Test report #{i}",
            created_at: (i + 1).days.ago
          )
        end

        get :index, params: { id: @project.id, tab: 'health_report', page: 1 }
        assert_response :success
        assert_select '.ai-helper-health-report-history table.list tbody tr', 10
      end

      should "display second page of health reports" do
        # Clean up existing reports
        AiHelperHealthReport.where(project: @project).destroy_all

        # Create 15 reports
        15.times do |i|
          AiHelperHealthReport.create!(
            project: @project,
            user: @user,
            health_report: "Test report #{i}",
            created_at: (i + 1).days.ago
          )
        end

        get :index, params: { id: @project.id, tab: 'health_report', page: 2 }
        assert_response :success
        assert_select '.ai-helper-health-report-history table.list tbody tr', 5
      end

      should "handle empty health report history" do
        # Clean up all reports
        AiHelperHealthReport.where(project: @project).destroy_all

        get :index, params: { id: @project.id, tab: 'health_report' }
        assert_response :success
        assert_select 'p.nodata', 1
      end
    end
  end
end
