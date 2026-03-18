require_relative '../test_helper'

class AiHelperModelProfilesControllerTest < ActionController::TestCase
  setup do
    AiHelperModelProfile.delete_all
    @request.session[:user_id] = 1 # Assuming user with ID 1 is an admin
    @model_profile = AiHelperModelProfile.create!(name: 'Test Profile', access_key: 'test_key', llm_type: "OpenAI", llm_model: "gpt-3.5-turbo")

  end

  should "show model profile" do
    get :show, params: { id: @model_profile.id }
    assert_response :success
    assert_template partial: '_show'
    assert_not_nil assigns(:model_profile)
  end

  should "get new model profile form" do
    get :new
    assert_response :success
    assert_template :new
    assert_not_nil assigns(:model_profile)
  end

  should "create model profile with valid attributes" do
    assert_difference('AiHelperModelProfile.count', 1) do
      post :create, params: { ai_helper_model_profile: { name: 'New Profile', access_key: 'new_key', llm_type: "OpenAI", llm_model: "model" } }
    end
    assert_redirected_to ai_helper_setting_path
  end

  should "not create model profile with invalid attributes" do
    assert_no_difference('AiHelperModelProfile.count') do
      post :create, params: { ai_helper_model_profile: { name: '', access_key: '' } }
    end
    assert_response :success
    assert_template :new
  end

  should "get edit model profile form" do
    get :edit, params: { id: @model_profile.id }
    assert_response :success
    assert_template :edit
    assert_not_nil assigns(:model_profile)
  end

  should "update model profile with valid attributes" do
    patch :update, params: { id: @model_profile.id, ai_helper_model_profile: { name: 'Updated Profile' } }
    assert_redirected_to ai_helper_setting_path
    @model_profile.reload
    assert_equal 'Updated Profile', @model_profile.name
  end

  should "not update model profile with invalid attributes" do
    patch :update, params: { id: @model_profile.id, ai_helper_model_profile: { name: '' } }
    assert_response :success
    assert_template :edit
    @model_profile.reload
    assert_not_equal '', @model_profile.name
  end

  should "destroy model profile" do
    assert_difference('AiHelperModelProfile.count', -1) do
      delete :destroy, params: { id: @model_profile.id }
    end
    assert_redirected_to ai_helper_setting_path
  end

  should "handle destroy for non-existent model profile" do
    assert_no_difference('AiHelperModelProfile.count') do
      delete :destroy, params: { id: 9999 } # Non-existent ID
    end
    assert_response :not_found
  end

  should "reject create without CSRF token when forgery protection is enabled" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :create, params: { ai_helper_model_profile: { name: 'New', access_key: 'key', llm_type: "OpenAI", llm_model: "model" } }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "reject destroy without CSRF token when forgery protection is enabled" do
    ActionController::Base.allow_forgery_protection = true
    begin
      delete :destroy, params: { id: @model_profile.id }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "reject JSON format create without CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :create, params: { ai_helper_model_profile: { name: 'New', access_key: 'key', llm_type: "OpenAI", llm_model: "model" }, format: :json }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "reject JSON format destroy without CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    begin
      delete :destroy, params: { id: @model_profile.id, format: :json }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  # T005: valid params for new profile returns { success: true }
  should "return success JSON when valid params are submitted for new profile" do
    provider_mock = mock("provider")
    chat_mock = mock("chat")
    chat_mock.expects(:ask).with("hi").returns(mock("message"))
    provider_mock.expects(:create_chat).returns(chat_mock)
    RedmineAiHelper::LlmProvider.expects(:get_provider_for_profile).returns(provider_mock)

    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: "real_key"
      }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
  end

  # T006: LLM raises exception returns { success: false, error: "..." }
  should "return failure JSON when LLM raises an exception" do
    provider_mock = mock("provider")
    chat_mock = mock("chat")
    chat_mock.expects(:ask).with("hi").raises(StandardError, "connection refused")
    provider_mock.expects(:create_chat).returns(chat_mock)
    RedmineAiHelper::LlmProvider.expects(:get_provider_for_profile).returns(provider_mock)

    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: "real_key"
      }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert_includes json["error"], "connection refused"
  end

  # T007: missing required fields returns 422 with { success: false, error: "..." }
  should "return 422 when required fields are missing" do
    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "",
        access_key: "real_key"
      }
    }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].present?
  end

  # T008: non-admin user is denied access
  should "deny access to non-admin user" do
    @request.session[:user_id] = 2 # non-admin user
    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: "real_key"
      }
    }
    assert_response 403
  end

  # T009: missing CSRF token returns 422
  should "return 422 for test_connection without CSRF token when forgery protection is enabled" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :test_connection, params: {
        ai_helper_model_profile: {
          llm_type: "OpenAI",
          llm_model: "gpt-3.5-turbo",
          access_key: "real_key"
        }
      }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  # T013: dummy key + valid id → uses DB access key
  should "use DB access key when dummy key is submitted with a valid profile id" do
    provider_mock = mock("provider")
    chat_mock = mock("chat")
    chat_mock.expects(:ask).with("hi").returns(mock("message"))
    provider_mock.expects(:create_chat).returns(chat_mock)
    RedmineAiHelper::LlmProvider.expects(:get_provider_for_profile).with do |profile|
      profile.access_key == "test_key"
    end.returns(provider_mock)

    post :test_connection, params: {
      id: @model_profile.id,
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: AiHelperModelProfilesController::DUMMY_ACCESS_KEY
      }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
  end

  # T014: non-dummy key + valid id → uses provided key (not DB key)
  should "use provided access key when non-dummy key is submitted with a valid profile id" do
    provider_mock = mock("provider")
    chat_mock = mock("chat")
    chat_mock.expects(:ask).with("hi").returns(mock("message"))
    provider_mock.expects(:create_chat).returns(chat_mock)
    RedmineAiHelper::LlmProvider.expects(:get_provider_for_profile).with do |profile|
      profile.access_key == "new_real_key"
    end.returns(provider_mock)

    post :test_connection, params: {
      id: @model_profile.id,
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: "new_real_key"
      }
    }
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
  end

  # T015: dummy key without id → returns 422 validation error
  should "return 422 when dummy key is submitted without a profile id" do
    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: AiHelperModelProfilesController::DUMMY_ACCESS_KEY
      }
    }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].present?
  end
end
