require_relative "../test_helper"

class AiHelperProjectSettingsControllerTest < ActionController::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules
  include Redmine::I18n
  setup do
    @project = Project.find(1)
    @user = User.find(1)
    @settings = AiHelperProjectSetting.settings(@project)
    User.current = @user
    @request.session[:user_id] = @user.id
    enabled_module = EnabledModule.new
    enabled_module.project_id = @project.id
    enabled_module.name = "ai_helper"
    enabled_module.save!
  end
  # Test for update action with valid parameters
  context "when updating settings with valid parameters" do
    should "update the settings and redirect with a success notice" do
      patch :update, params: {
                       id: @project.id,
                       setting: {
                         issue_draft_instructions: "New instructions",
                         subtask_instructions: "New subtask",
                         lock_version: @settings.lock_version,
                       },
                     }
      assert_redirected_to ai_helper_dashboard_path(id: @project, tab: "settings")
      assert_equal I18n.t(:notice_successful_update), flash[:notice]
      @settings.reload
      assert_equal "New instructions", @settings.issue_draft_instructions
      assert_equal "New subtask", @settings.subtask_instructions
    end
  end

  # Test for update action with invalid parameters (simulate save failure)
  context "when updating settings fails" do
    should "redirect with an lock error notice" do
      lock_version = @settings.lock_version
      @settings.issue_draft_instructions = "aaaa"
      @settings.save!

      patch :update, params: {
                       id: @project.id,
                       setting: {
                         issue_draft_instructions: "Invalid instructions",
                         subtask_instructions: "Invalid subtask",
                         lock_version: lock_version,
                       },
                     }
      assert_redirected_to ai_helper_dashboard_path(id: @project, tab: "settings")
      assert_equal I18n.t(:notice_locking_conflict), flash[:error]
    end

    should "redirect with an error notice" do
      @settings.stubs(:save).returns(false)
      AiHelperProjectSetting.stubs(:settings).returns(@settings)

      patch :update, params: {
                       id: @project.id,
                       setting: {
                         issue_draft_instructions: "Invalid instructions",
                         subtask_instructions: "Invalid subtask",
                         lock_version: @settings.lock_version,
                       },
                     }
      assert_redirected_to ai_helper_dashboard_path(id: @project, tab: "settings")
    end
  end
end
