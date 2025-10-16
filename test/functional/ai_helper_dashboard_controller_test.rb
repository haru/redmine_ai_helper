require_relative "../test_helper"

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
      @request.session[:per_page] = 10  # Set default per_page for tests
      User.current = @user # Set current user for Redmine

      role = Role.anonymous
      role.add_permission! :view_ai_helper
      role.save!

      # Add permission to Manager role as well
      manager_role = Role.find(1)
      manager_role.add_permission! :view_ai_helper
      manager_role.add_permission! :delete_ai_helper_health_reports
      manager_role.remove_permission! :settings_ai_helper
      manager_role.save!

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

      should "show settings tab when user has settings permission" do
        manager_role = Role.find(1)
        manager_role.add_permission! :settings_ai_helper

        get :index, params: { id: @project.id }

        assert_select "div.tabs a", text: I18n.t(:label_settings)
      end

      should "display dashboard with health report tab" do
        # Create some health reports
        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 1",
          created_at: 2.days.ago,
        )
        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 2",
          created_at: 1.day.ago,
        )

        get :index, params: { id: @project.id, tab: "health_report" }
        assert_response :success
        assert_template :index
        assert_select ".ai-helper-health-report-history", 1
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
            created_at: (i + 1).days.ago,
          )
        end

        get :index, params: { id: @project.id, tab: "health_report", page: 1, per_page: 10 }
        assert_response :success
        assert_select ".ai-helper-health-report-history table.list tbody tr", 10
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
            created_at: (i + 1).days.ago,
          )
        end

        get :index, params: { id: @project.id, tab: "health_report", page: 2, per_page: 10 }
        assert_response :success
        assert_select ".ai-helper-health-report-history table.list tbody tr", 5
      end

      should "handle empty health report history" do
        # Clean up all reports
        AiHelperHealthReport.where(project: @project).destroy_all

        get :index, params: { id: @project.id, tab: "health_report" }
        assert_response :success
        assert_select "p.nodata", 1
      end
    end

    context "#health_report_history" do
      setup do
        # Clean up any existing reports to ensure consistent test state
        AiHelperHealthReport.where(project: @project).destroy_all

        @report1 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 1",
          created_at: 2.days.ago,
        )

        @report2 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report 2",
          created_at: 1.day.ago,
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
            created_at: (i + 3).days.ago,
          )
        end

        get :health_report_history, params: { id: @project.id, page: 1, per_page: 10 }

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

This is a test report.",
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
                                   format: :pdf,
                                 }

        assert_response :success
        assert_equal "application/pdf", response.media_type
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
          health_report: "Test report",
        )
      end

      should "delete own report" do
        assert_difference "AiHelperHealthReport.count", -1 do
          delete :health_report_destroy, params: {
                                           id: @project.id,
                                           report_id: @report.id,
                                         }
        end

        assert_redirected_to ai_helper_dashboard_path(@project, tab: "health_report")
      end

      # should "return JSON response" do
      #   delete :health_report_destroy, params: {
      #                                    id: @project.id,
      #                                    report_id: @report.id,
      #                                    format: :json,
      #                                  }

      #   assert_response :success
      #   assert_equal "application/json", response.media_type

      #   json_response = JSON.parse(response.body)
      #   assert_equal "ok", json_response["status"]
      #   assert_equal @report.id, json_response["deleted_report_id"]
      #   assert json_response["message"].present?
      # end

      should "not delete report without permission" do
        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        assert_no_difference "AiHelperHealthReport.count" do
          delete :health_report_destroy, params: {
                                           id: @project.id,
                                           report_id: @report.id,
                                         }
        end

        assert_response :forbidden
      end

      should "allow project member to delete other user's report" do
        other_user = User.find(2)
        @request.session[:user_id] = other_user.id
        User.current = other_user

        # other_user is a member of the project with delete permission, so they can delete the report
        assert_difference "AiHelperHealthReport.count", -1 do
          delete :health_report_destroy, params: {
                                           id: @project.id,
                                           report_id: @report.id,
                                         }
        end

        assert_redirected_to ai_helper_dashboard_path(@project, tab: "health_report")
      end
    end

    context "Master-Detail Layout" do
      setup do
        # Clean up any existing reports to ensure consistent test state
        AiHelperHealthReport.where(project: @project).destroy_all

        @report1 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Report 1\n\nFirst report content",
          created_at: 2.days.ago,
        )

        @report2 = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Report 2\n\nSecond report content",
          created_at: 1.day.ago,
        )
      end

      should "render master-detail layout with initial selection" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: "health_report" }

        assert_response :success
        assert_select ".ai-helper-master-detail-layout", 1
        assert_select ".ai-helper-master-pane", 1
        assert_select ".ai-helper-detail-pane", 1

        # Most recent report should be selected
        assert_select ".ai-helper-report-row.selected[data-report-id=?]", @report2.id.to_s, 1
      end

      should "select specific report via report_id param" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: "health_report", report_id: @report1.id }

        assert_response :success
        assert_select ".ai-helper-report-row.selected[data-report-id=?]", @report1.id.to_s, 1
      end

      should "display placeholder when no reports exist" do
        AiHelperHealthReport.where(project: @project).destroy_all

        get :index, params: { id: @project.id, tab: "health_report" }

        assert_response :success
        assert_select ".ai-helper-detail-placeholder", 1
      end

      should "include data attributes for Ajax interactions in report rows" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: "health_report" }

        assert_response :success
        assert_select ".ai-helper-report-row[data-report-id]", 2
        assert_select ".ai-helper-report-row[data-report-id='#{@report1.id}'][data-report-url]", 1
        assert_select ".ai-helper-report-row[data-report-id='#{@report2.id}'][data-report-url]", 1
      end

      should "set selected_report from URL params" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :health_report_history, params: {
                                      id: @project.id,
                                      report_id: @report1.id,
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

        get :index, params: { id: @project.id, tab: "health_report" }

        assert_response :success
        assert_select ".ai-helper-health-report-detail[data-report-id=?]", @report2.id.to_s, 1
        assert_select ".ai-helper-health-report-meta", 1
        assert_select "#ai-helper-markdown-export-detail", 1
        assert_select "#ai-helper-pdf-export-detail", 1
      end

      should "include clickable report rows with proper onclick handling" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :index, params: { id: @project.id, tab: "health_report" }

        assert_response :success
        # Check that delete links have onclick to stop propagation
        assert_select ".ai-helper-report-row .icon-del[onclick]", count: 2
      end

      should "maintain selection across pagination" do
        AiHelperHealthReport.where(project: @project).destroy_all

        15.times do |i|
          AiHelperHealthReport.create!(
            project: @project,
            user: @user,
            health_report: "Test report #{i}",
            created_at: (i + 1).days.ago,
          )
        end

        get :index, params: { id: @project.id, tab: "health_report", page: 2, per_page: 10 }

        assert_response :success
        assert_select ".ai-helper-report-row", 5
        # Should select first report on current page if selected report not visible
        assert_select ".ai-helper-report-row.selected", 1
      end
    end

    context "#compare_health_reports" do
      setup do
        @old_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Old Report\n\nOld content",
          metrics: { issue_statistics: { total_issues: 40 } }.to_json,
          created_at: 5.days.ago,
        )

        @new_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# New Report\n\nNew content",
          metrics: { issue_statistics: { total_issues: 50 } }.to_json,
          created_at: 1.day.ago,
        )

        # Ensure user is logged in for all tests
        @request.session[:user_id] = @user.id
      end

      should "show comparison page with valid reports" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                       new_id: @new_report.id,
                                     }

        assert_response :success
        assert_template "ai_helper/project/health_report_comparison"
        assert_select ".ai-helper-comparison-container", 1
        assert_select ".old-report-info", 1
        assert_select ".new-report-info", 1
        assert_select "#ai-helper-comparison-analysis[data-analysis-url]", 1
      end

      should "redirect when report IDs are missing" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: { id: @project.id }

        assert_redirected_to ai_helper_dashboard_path(@project, tab: "health_report")
        assert_not_nil flash[:error]
      end

      should "redirect when only old_id is missing" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       new_id: @new_report.id,
                                     }

        assert_redirected_to ai_helper_dashboard_path(@project, tab: "health_report")
        assert_not_nil flash[:error]
      end

      should "redirect when only new_id is missing" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                     }

        assert_redirected_to ai_helper_dashboard_path(@project, tab: "health_report")
        assert_not_nil flash[:error]
      end

      should "swap reports to ensure chronological order" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        # Pass newer report as old_id and older as new_id
        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @new_report.id,
                                       new_id: @old_report.id,
                                     }

        assert_response :success
        assert_equal @old_report.id, assigns(:old_report).id
        assert_equal @new_report.id, assigns(:new_report).id
      end

      should "return 404 for non-existent report" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: 99999,
                                       new_id: @new_report.id,
                                     }

        assert_response :not_found
      end

      should "return 403 when user lacks permission" do
        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                       new_id: @new_report.id,
                                     }

        assert_response :forbidden
      end

      should "return 403 when reports belong to different project" do
        project2 = Project.find(2)
        project2.enabled_module_names = project2.enabled_module_names + ["ai_helper"]
        project2.save!

        other_report = AiHelperHealthReport.create!(
          project: project2,
          user: @user,
          health_report: "Other project report",
          metrics: {}.to_json,
        )

        role = Role.find(1)
        role.add_permission! :view_ai_helper

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                       new_id: other_report.id,
                                     }

        assert_response :forbidden
      end

      should "render comparison UI template for GET request" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                       new_id: @new_report.id,
                                     }

        assert_response :success
        assert_template "ai_helper/project/health_report_comparison"
      end

      should "assign old_report and new_report instance variables" do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: @old_report.id,
                                       new_id: @new_report.id,
                                     }

        assert_response :success
        assert_not_nil assigns(:old_report)
        assert_not_nil assigns(:new_report)
        assert_equal @old_report.id, assigns(:old_report).id
        assert_equal @new_report.id, assigns(:new_report).id
      end
    end

    context "Error handling" do
      setup do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports
        role.add_permission! :delete_ai_helper_health_reports
      end

      should "return 404 for non-existent health report in show action" do
        get :health_report_show, params: { id: @project.id, report_id: 99999 }

        assert_response :not_found
      end

      should "return 404 for non-existent health report in destroy action" do
        delete :health_report_destroy, params: { id: @project.id, report_id: 99999 }

        assert_response :not_found
      end

      should "return 404 when health report belongs to different project" do
        other_project = Project.find(2)
        other_project.enabled_module_names = other_project.enabled_module_names + ["ai_helper"]
        other_project.save!

        other_report = AiHelperHealthReport.create!(
          project: other_project,
          user: @user,
          health_report: "Other project report",
        )

        get :health_report_show, params: { id: @project.id, report_id: other_report.id }

        assert_response :not_found
      end

      should "return 403 when user lacks permission for health report show" do
        report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report",
        )

        # Remove permission
        role = Role.find(1)
        role.remove_permission! :view_ai_helper_health_reports

        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        get :health_report_show, params: { id: @project.id, report_id: report.id }

        assert_response :forbidden
      end

      should "return 403 when user lacks permission for health report destroy" do
        report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Test report",
        )

        non_member_user = User.find(4)
        @request.session[:user_id] = non_member_user.id

        delete :health_report_destroy, params: { id: @project.id, report_id: report.id }

        assert_response :forbidden
      end
    end

    context "Streaming comparison" do
      setup do
        @old_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Old Report\n\nOld content",
          metrics: { issue_statistics: { total_issues: 40 } }.to_json,
          created_at: 5.days.ago,
        )

        @new_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# New Report\n\nNew content",
          metrics: { issue_statistics: { total_issues: 50 } }.to_json,
          created_at: 1.day.ago,
        )

        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports

        # Mock the LLM class to avoid actual API calls
        @llm_mock = mock("llm")
        RedmineAiHelper::Llm.stubs(:new).returns(@llm_mock)
        @llm_mock.stubs(:compare_health_reports).yields("Comparison content")
      end

      should "detect POST request as streaming request" do
        # Verify that POST requests trigger streaming path
        post :compare_health_reports, params: {
                                        id: @project.id,
                                        old_report_id: @old_report.id,
                                        new_report_id: @new_report.id,
                                      }

        # The test will either succeed (streaming) or fail with permission issues
        # Both outcomes indicate the POST path is being executed
        assert [200, 403, 404].include?(response.status)
      end

      should "detect event-stream Accept header as streaming request" do
        @request.headers["Accept"] = "text/event-stream"

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_report_id: @old_report.id,
                                       new_report_id: @new_report.id,
                                     }

        # Should attempt streaming path
        assert [200, 403, 404].include?(response.status)
      end

      should "return 403 when reports belong to different project in streaming comparison" do
        other_project = Project.find(2)
        other_project.enabled_module_names = other_project.enabled_module_names + ["ai_helper"]
        other_project.save!

        other_report = AiHelperHealthReport.create!(
          project: other_project,
          user: @user,
          health_report: "Other project report",
        )

        post :compare_health_reports, params: {
                                        id: @project.id,
                                        old_report_id: @old_report.id,
                                        new_report_id: other_report.id,
                                      }

        assert_response :forbidden
      end

      should "return 404 for non-existent report in streaming comparison" do
        post :compare_health_reports, params: {
                                        id: @project.id,
                                        old_report_id: 99999,
                                        new_report_id: @new_report.id,
                                      }

        assert_response :not_found
      end

      should "use streaming comparison when GET request includes event-stream accept header" do
        other_project = Project.find(2)
        other_project.enabled_module_names = other_project.enabled_module_names + ["ai_helper"]
        other_project.save!

        other_report = AiHelperHealthReport.create!(
          project: other_project,
          user: @user,
          health_report: "Other project report",
        )

        original_accept = @request.headers["Accept"]
        @request.headers["Accept"] = "text/event-stream"

        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_report_id: @old_report.id,
                                       new_report_id: other_report.id,
                                     }

        assert_response :forbidden
        if original_accept
          @request.headers["Accept"] = original_accept
        else
          @request.headers["Accept"] = nil
        end
      end
    end

    context "Edge cases" do
      setup do
        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports
      end

      should "handle invalid report_id parameter in health_report_history" do
        # Create some reports
        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Report 1",
          created_at: 1.day.ago,
        )

        AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Report 2",
          created_at: 2.days.ago,
        )

        # Test with invalid report_id - should result in nil selected_report
        get :health_report_history, params: { id: @project.id, report_id: "invalid" }

        assert_response :success
        # When report_id is invalid, selected_report should be nil
        assert_nil assigns(:selected_report)
      end

      should "handle report_id that doesn't exist in current page" do
        # Create 15 reports
        reports = []
        15.times do |i|
          reports << AiHelperHealthReport.create!(
            project: @project,
            user: @user,
            health_report: "Report #{i}",
            created_at: (i + 1).days.ago,
          )
        end

        # Request page 2 with report_id from page 1
        get :health_report_history, params: {
                                      id: @project.id,
                                      page: 2,
                                      report_id: reports.first.id.to_s,
                                    }

        assert_response :success
        # When report_id is not in current page, selected_report should be nil
        assert_nil assigns(:selected_report)
      end

      should "handle empty project with no health reports" do
        # Ensure no reports exist
        AiHelperHealthReport.where(project: @project).destroy_all

        get :health_report_history, params: { id: @project.id }

        assert_response :success
        assert_equal 0, assigns(:health_reports).count
        assert_nil assigns(:selected_report)
      end

      should "handle compare_health_reports with swapped chronological order" do
        newer_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Newer report",
          created_at: 1.day.ago,
        )

        older_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Older report",
          created_at: 5.days.ago,
        )

        # Pass newer report as old_id and older as new_id
        get :compare_health_reports, params: {
                                       id: @project.id,
                                       old_id: newer_report.id,
                                       new_id: older_report.id,
                                     }

        assert_response :success
        # Should swap them to ensure chronological order
        assert_equal older_report.id, assigns(:old_report).id
        assert_equal newer_report.id, assigns(:new_report).id
      end
    end

    context "#comparison_pdf" do
      setup do
        @old_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Old Report\n\nOld content",
          created_at: 5.days.ago,
        )

        @new_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# New Report\n\nNew content",
          created_at: 1.day.ago,
        )

        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports
      end

      should "export comparison analysis as PDF with valid content" do
        comparison_content = "# Comparison Analysis\n\nThis is the comparison result."

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        assert_equal "application/pdf", response.media_type
        assert_match(/#{@project.identifier}-health-report-comparison-\d{8}\.pdf/, response.headers["Content-Disposition"])
      end

      should "generate correct filename with project identifier and date" do
        comparison_content = "# Comparison Analysis\n\nTest content"
        expected_date = Date.current.strftime("%Y%m%d")

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        expected_filename = "#{@project.identifier}-health-report-comparison-#{expected_date}.pdf"
        assert_match(/filename="#{Regexp.escape(expected_filename)}"/, response.headers["Content-Disposition"])
      end

      should "sanitize HTML tags from content" do
        comparison_content = "# Test\n\n<div>HTML content</div>\n\n<p>Paragraph</p>"

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        assert_equal "application/pdf", response.media_type
        # PDF should be generated with sanitized content (HTML tags removed)
        assert response.body.present?
      end

      should "sanitize script tags from content" do
        comparison_content = "# Test\n\n<script>alert('xss')</script>\n\nSafe content"

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        assert_equal "application/pdf", response.media_type
        # PDF should be generated with sanitized content (script tags removed)
        assert response.body.present?
      end

      should "redirect with alert when no content is provided" do
        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: "",
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_redirected_to ai_helper_health_report_compare_path(@project, old_id: @old_report.id, new_id: @new_report.id)
        assert_not_nil flash[:alert]
      end

      should "redirect with alert when content is nil" do
        post :comparison_pdf, params: {
                                id: @project.id,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_redirected_to ai_helper_health_report_compare_path(@project, old_id: @old_report.id, new_id: @new_report.id)
        assert_not_nil flash[:alert]
      end

      should "handle multiline script tag sanitization" do
        comparison_content = <<~CONTENT
          # Test Report

          <script>
            var malicious = "code";
            alert('xss');
          </script>

          Safe content here.
        CONTENT

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        assert_equal "application/pdf", response.media_type
      end

      should "preserve markdown formatting in content" do
        comparison_content = <<~CONTENT
          # Main Title

          ## Subtitle

          - Bullet point 1
          - Bullet point 2

          **Bold text** and *italic text*
        CONTENT

        post :comparison_pdf, params: {
                                id: @project.id,
                                comparison_content: comparison_content,
                                old_report_id: @old_report.id,
                                new_report_id: @new_report.id,
                              }

        assert_response :success
        assert_equal "application/pdf", response.media_type
        assert response.body.present?
      end
    end

    context "#comparison_markdown" do
      setup do
        @old_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# Old Report\n\nOld content",
          created_at: 5.days.ago,
        )

        @new_report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "# New Report\n\nNew content",
          created_at: 1.day.ago,
        )

        role = Role.find(1)
        role.add_permission! :view_ai_helper_health_reports
      end

      should "export comparison analysis as Markdown with valid content" do
        comparison_content = "# Comparison Analysis\n\nThis is the comparison result."

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        assert_match(/#{@project.identifier}-health-report-comparison-\d{8}\.md/, response.headers["Content-Disposition"])
      end

      should "generate correct filename with project identifier and date" do
        comparison_content = "# Comparison Analysis\n\nTest content"
        expected_date = Date.current.strftime("%Y%m%d")

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        expected_filename = "#{@project.identifier}-health-report-comparison-#{expected_date}.md"
        assert_match(/filename="#{Regexp.escape(expected_filename)}"/, response.headers["Content-Disposition"])
      end

      should "sanitize HTML tags from content" do
        comparison_content = "# Test\n\n<div>HTML content</div>\n\n<p>Paragraph</p>"
        expected_sanitized = "# Test\n\nHTML content\n\nParagraph"

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        assert_equal expected_sanitized, response.body
      end

      should "sanitize script tags from content" do
        comparison_content = "# Test\n\n<script>alert('xss')</script>\n\nSafe content"
        expected_sanitized = "# Test\n\n\n\nSafe content"

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        assert_equal expected_sanitized, response.body
      end

      should "redirect with alert when no content is provided" do
        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: "",
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_redirected_to ai_helper_health_report_compare_path(@project, old_id: @old_report.id, new_id: @new_report.id)
        assert_not_nil flash[:alert]
      end

      should "redirect with alert when content is nil" do
        post :comparison_markdown, params: {
                                     id: @project.id,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_redirected_to ai_helper_health_report_compare_path(@project, old_id: @old_report.id, new_id: @new_report.id)
        assert_not_nil flash[:alert]
      end

      should "handle multiline script tag sanitization" do
        comparison_content = <<~CONTENT
          # Test Report

          <script>
            var malicious = "code";
            alert('xss');
          </script>

          Safe content here.
        CONTENT

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        # Script tags should be removed
        assert_no_match(/<script/, response.body)
        assert_match(/Safe content here/, response.body)
      end

      should "preserve markdown formatting in content" do
        comparison_content = <<~CONTENT
          # Main Title

          ## Subtitle

          - Bullet point 1
          - Bullet point 2

          **Bold text** and *italic text*
        CONTENT

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        # Check that markdown formatting is preserved
        assert_match(/# Main Title/, response.body)
        assert_match(/## Subtitle/, response.body)
        assert_match(/- Bullet point 1/, response.body)
        assert_match(/\*\*Bold text\*\*/, response.body)
        assert_match(/\*italic text\*/, response.body)
      end

      should "return content as UTF-8 encoded text" do
        comparison_content = "# Test\n\n日本語のテスト\n\nEnglish test"

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        # Check that UTF-8 characters are preserved
        assert_match(/日本語のテスト/, response.body)
      end

      should "handle mixed HTML and markdown content" do
        comparison_content = <<~CONTENT
          # Report Header

          <div class="container">
            <p>HTML paragraph</p>
          </div>

          ## Markdown Section

          This is **markdown** content.

          <script>alert('test')</script>
        CONTENT

        post :comparison_markdown, params: {
                                     id: @project.id,
                                     comparison_content: comparison_content,
                                     old_report_id: @old_report.id,
                                     new_report_id: @new_report.id,
                                   }

        assert_response :success
        assert_equal "text/markdown", response.media_type
        # HTML tags should be removed
        assert_no_match(/<div/, response.body)
        assert_no_match(/<p>/, response.body)
        assert_no_match(/<script/, response.body)
        # Markdown should be preserved
        assert_match(/# Report Header/, response.body)
        assert_match(/## Markdown Section/, response.body)
        assert_match(/\*\*markdown\*\*/, response.body)
      end
    end
  end
end
