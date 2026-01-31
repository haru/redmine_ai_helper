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
end
