require_relative '../test_helper'

class AiHelperSettingsControllerTest < ActionController::TestCase
  setup do
    AiHelperSetting.delete_all
    AiHelperModelProfile.delete_all
    @request.session[:user_id] = 1 # Assuming user with ID 1 is an admin

    @model_profile = AiHelperModelProfile.create!(name: 'Test Profile', access_key: 'test_key', llm_type: "OpenAI", llm_model: "gpt-3.5-turbo")
    @model_profile.reload
    @ai_helper_setting = AiHelperSetting.find_or_create
  end

  should "get index" do
    get :index
    assert_response :success
    assert_template :index
    assert_not_nil assigns(:setting)
    assert_not_nil assigns(:model_profiles)
  end

  should "update setting with valid attributes" do
    post :update, params: { ai_helper_setting: { model_profile_id: @model_profile.id } }
    assert_redirected_to action: :index
    @ai_helper_setting.reload
    assert_equal @model_profile.id, @ai_helper_setting.model_profile_id
  end

  should "not update setting with invalid attributes" do
    post :update, params: { id: @ai_helper_setting,  ai_helper_setting: { some_attribute: nil } }
    assert_response :redirect
    assert_not_nil assigns(:setting)
    assert_not_nil assigns(:model_profiles)
  end

  should "reject update without CSRF token when forgery protection is enabled" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :update, params: { ai_helper_setting: { model_profile_id: @model_profile.id } }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "reject JSON format update without CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :update, params: { ai_helper_setting: { model_profile_id: @model_profile.id }, format: :json }
      assert_response 422
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end
end
