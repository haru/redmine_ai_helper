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

    context "#health_report_history" do
      setup do
        @report1 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 1",
          created_at: 2.days.ago
        )

        @report2 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 2",
          created_at: 1.day.ago
        )
      end

      should "display health report history for project" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_history, params: { id: @project.id }

        assert_response :success
        assert_template partial: "ai_helper/project/_health_report_history"
        assert_not_nil assigns(:health_reports)
        assert_equal 2, assigns(:health_reports).count
      end

      should "paginate results" do
        AiHelperHealthReport.where(project: @project).destroy_all

        15.times do |i|
          AiHelperHealthReport.create!(
            project: @project,
            user: @user,
            health_report: "Test report #{i}",
            created_at: (i + 3).days.ago
          )
        end

        get :health_report_history, params: { id: @project.id, page: 1 }

        assert_response :success
        assert_equal 10, assigns(:health_reports).count
      end
    end

    context "#health_report_show" do
      setup do
        @report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Test Report

This is a test report."
        )
      end

      should "display health report detail" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_show, params: { id: @project.id, report_id: @report.id }

        assert_response :success
        assert_template "ai_helper/project/health_report_show"
        assert_not_nil assigns(:health_report)
        assert_equal @report.id, assigns(:health_report).id
      end

      should "generate PDF export" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_show, params: {
          id: @project.id,
          report_id: @report.id,
          format: :pdf
        }

        assert_response :success
        assert_equal 'application/pdf', response.media_type
      end

      should "return 403 when user does not have permission" do
        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        get :health_report_show, params: { id: @project.id, report_id: @report.id }

        assert_response :forbidden
      end
    end

    context "#health_report_destroy" do
      setup do
        @report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report"
        )
      end

      should "delete own report" do
        assert_difference 'AiHelperHealthReport.count', -1 do
          delete :health_report_destroy, params: {
            id: @project.id,
            report_id: @report.id
          }
        end

        assert_redirected_to ai_helper_dashboard_path(@project, tab: 'health_report')
      end

      should "not delete report without permission" do
        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        assert_no_difference 'AiHelperHealthReport.count' do
          delete :health_report_destroy, params: {
            id: @project.id,
            report_id: @report.id
          }
        end

        assert_response :forbidden
      end

      should "not delete other user's report without permission" do
        other_user = User.find(2)
        @request.session[:user_id] = other_user.id

        role = Role.find(1)
        role.add_permission! :delete_ai_helper_health_reports

        assert_no_difference 'AiHelperHealthReport.count' do
          delete :health_report_destroy, params: {
            id: @project.id,
            report_id: @report.id
          }
        end

        assert_response :forbidden
      end
    end

    context "Master-Detail Layout" do
      setup do
        @report1 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Report 1\n\nFirst report content",
          created_at: 2.days.ago
        )

        @report2 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Report 2\n\nSecond report content",
          created_at: 1.day.ago
        )
      end

      should "render master-detail layout with initial selection" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: 'health_report' }

        assert_response :success
        assert_select '.ai-helper-master-detail-layout', 1
        assert_select '.ai-helper-master-pane', 1
        assert_select '.ai-helper-detail-pane', 1

        # Most recent report should be selected
        assert_select '.ai-helper-report-row.selected[data-report-id=?]', @report2.id.to_s, 1
      end

      should "select specific report via report_id param" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: 'health_report', report_id: @report1.id }

        assert_response :success
        assert_select '.ai-helper-report-row.selected[data-report-id=?]', @report1.id.to_s, 1
      end

      should "display placeholder when no reports exist" do
        AiHelperHealthReport.where(project: @project).destroy_all

        get :index, params: { id: @project.id, tab: 'health_report' }

        assert_response :success
        assert_select '.ai-helper-detail-placeholder', 1
      end

      should "include data attributes for Ajax interactions in report rows" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: 'health_report' }

        assert_response :success
        assert_select '.ai-helper-report-row[data-report-id]', 2
        assert_select ".ai-helper-report-row[data-report-id='#{@report1.id}'][data-report-url]", 1
        assert_select ".ai-helper-report-row[data-report-id='#{@report2.id}'][data-report-url]", 1
      end

      should "set selected_report from URL params" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_history, params: {
          id: @project.id,
          report_id: @report1.id
        }

        assert_response :success
        assert_not_nil assigns(:selected_report)
        assert_equal @report1.id, assigns(:selected_report).id
      end

      should "default to most recent report when no report_id specified" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_history, params: { id: @project.id }

        assert_response :success
        assert_not_nil assigns(:selected_report)
        assert_equal @report2.id, assigns(:selected_report).id
      end

      should "render health_report_detail_pane partial with report data" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: 'health_report' }

        assert_response :success
        assert_select '.ai-helper-health-report-detail[data-report-id=?]', @report2.id.to_s, 1
        assert_select '.ai-helper-health-report-meta', 1
        assert_select '#ai-helper-markdown-export-detail', 1
        assert_select '#ai-helper-pdf-export-detail', 1
      end

      should "include clickable report rows with proper onclick handling" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: 'health_report' }

        assert_response :success
        # Check that delete links have onclick to stop propagation
        assert_select '.ai-helper-report-row .icon-del[onclick]', count: 2
      end

      should "maintain selection across pagination" do
        AiHelperHealthReport.where(project: @project).destroy_all

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
        assert_select '.ai-helper-report-row', 5
        # Should select first report on current page if selected report not visible
        assert_select '.ai-helper-report-row.selected', 1
      end
    end

  end
end
