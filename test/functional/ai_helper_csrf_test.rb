# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

# Tests to verify that CSRF protection is properly enforced for non-streaming POST actions
# and properly exempted for streaming/API actions.
class AiHelperCsrfTest < ActionController::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles, :wikis, :wiki_pages, :wiki_contents

  def setup
    @controller = AiHelperController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create
    @user = User.find(1)
    @project = projects(:projects_001)

    enabled_module = EnabledModule.new
    enabled_module.project_id = @project.id
    enabled_module.name = "ai_helper"
    enabled_module.save!

    @request.session[:user_id] = @user.id

    # Enable forgery protection for CSRF testing
    ActionController::Base.allow_forgery_protection = true
  end

  def teardown
    ActionController::Base.allow_forgery_protection = false
  end

  # --- Actions that SHOULD enforce CSRF protection ---

  def test_suggest_completion_rejects_post_without_csrf_token
    @request.headers["Content-Type"] = "application/json"
    post :suggest_completion,
         params: { id: @project.id, issue_id: 1 },
         body: { text: "test text", cursor_position: 4 }.to_json

    assert_response 422
  end

  def test_suggest_wiki_completion_rejects_post_without_csrf_token
    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { id: @project.id },
         body: { text: "test text", cursor_position: 4 }.to_json

    assert_response 422
  end

  def test_check_typos_rejects_post_without_csrf_token
    post :check_typos,
         params: { id: @project.id, text: "test text", context_type: "issue" }

    assert_response 422
  end

  def test_check_duplicates_rejects_post_without_csrf_token
    @request.headers["Content-Type"] = "application/json"
    post :check_duplicates,
         params: { id: @project.id },
         body: { subject: "Test subject", description: "Test description" }.to_json

    assert_response 422
  end

  # --- Actions that SHOULD be exempt from CSRF protection ---

  def test_generate_project_health_allows_get_without_csrf_token
    # Stub LLM to avoid actual API calls
    llm_mock = mock("RedmineAiHelper::Llm")
    llm_mock.stubs(:project_health_report).returns("Health report content")
    RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

    get :generate_project_health, params: { id: @project.id }

    # Should not be 422 (CSRF rejection)
    assert_not_equal 422, @response.status
  end

  def test_api_create_health_report_allows_post_without_csrf_token
    # Use API key authentication instead of session
    @user.generate_api_key if @user.api_key.blank?

    post :api_create_health_report,
         params: { id: @project.id, format: :json, key: @user.api_key }

    # Should not be 422 (CSRF rejection)
    assert_not_equal 422, @response.status
  end
end
