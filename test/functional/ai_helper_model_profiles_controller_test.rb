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
    RedmineAiHelper::LlmProvider.expects(:provider_for_profile).returns(provider_mock)

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
    RedmineAiHelper::LlmProvider.expects(:provider_for_profile).returns(provider_mock)

    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAI",
        llm_model: "gpt-3.5-turbo",
        access_key: "real_key"
      }
    }
    assert_response :internal_server_error
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
    RedmineAiHelper::LlmProvider.expects(:provider_for_profile).with do |profile|
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
    RedmineAiHelper::LlmProvider.expects(:provider_for_profile).with do |profile|
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

  # T010: missing base_uri for OpenAICompatible returns 422
  should "return 422 when base_uri is missing for OpenAICompatible" do
    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "OpenAICompatible",
        llm_model: "some-model",
        access_key: "key",
        base_uri: ""
      }
    }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].present?
  end

  # T011: missing base_uri for AzureOpenAi returns 422
  should "return 422 when base_uri is missing for AzureOpenAi" do
    post :test_connection, params: {
      ai_helper_model_profile: {
        llm_type: "AzureOpenAi",
        llm_model: "gpt-4",
        access_key: "key",
        base_uri: ""
      }
    }
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal false, json["success"]
    assert json["error"].present?
  end

  # T028 [US2]: unregistered model → list_models is called → test_connection succeeds
  should "auto-fetch model via list_models when model is not in registry during test_connection" do
    unregistered_model_id = "gpt-unregistered-controller-test-888"
    RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == unregistered_model_id }

    unregistered_profile = AiHelperModelProfile.create!(
      name: "Unregistered Controller Test Profile",
      llm_type: "OpenAI",
      llm_model: unregistered_model_id,
      access_key: "test_key",
    )

    begin
      # Return a real OpenAiProvider so ensure_model_registered! runs through it
      real_provider = RedmineAiHelper::LlmClient::OpenAiProvider.new(model_profile: unregistered_profile)
      RedmineAiHelper::LlmProvider.stubs(:provider_for_profile).returns(real_provider)

      # Stub list_models on any OpenAI provider instance (triggered by fetch_and_register_model!)
      fetched_model = RubyLLM::Model::Info.new(
        id: unregistered_model_id, provider: "openai", name: "GPT Unregistered Controller Test",
      )
      RubyLLM::Providers::OpenAI.any_instance.expects(:list_models).at_least_once.returns([fetched_model])

      # Stub chat.ask to avoid real API calls
      RubyLLM::Chat.any_instance.stubs(:ask).returns(stub("message"))

      post :test_connection, params: {
        ai_helper_model_profile: {
          llm_type: "OpenAI",
          llm_model: unregistered_model_id,
          access_key: "test_key",
        }
      }
      assert_response :success
      json = JSON.parse(response.body)
      assert_equal true, json["success"]
    ensure
      unregistered_profile.destroy
      RubyLLM.models.instance_variable_get(:@models).reject! { |m| m.id == unregistered_model_id }
    end
  end

  context "copy action" do
    should "copy model profile with valid name" do
      assert_difference('AiHelperModelProfile.count', 1) do
        post :copy, params: { id: @model_profile.id, name: 'Copied Profile' }
      end
      assert_response :success
      response_json = JSON.parse(response.body)
      assert response_json['success']
      assert_equal flash[:notice], I18n.t(:notice_successful_create)

      copied = AiHelperModelProfile.find_by(name: 'Copied Profile')
      assert_not_nil copied
      assert_equal @model_profile.llm_type, copied.llm_type
      assert_equal @model_profile.access_key, copied.access_key
      assert_equal @model_profile.llm_model, copied.llm_model
    end

    should "not copy model profile with blank name" do
      assert_no_difference('AiHelperModelProfile.count') do
        post :copy, params: { id: @model_profile.id, name: '' }
      end
      assert_response :unprocessable_entity
      response_json = JSON.parse(response.body)
      assert_not response_json['success']
      assert response_json['errors'].present?
    end

    should "not copy model profile with duplicate name" do
      AiHelperModelProfile.create!(name: 'Existing Profile', access_key: 'key2',
                                    llm_type: 'OpenAI', llm_model: 'gpt-4')
      assert_no_difference('AiHelperModelProfile.count') do
        post :copy, params: { id: @model_profile.id, name: 'Existing Profile' }
      end
      assert_response :unprocessable_entity
      response_json = JSON.parse(response.body)
      assert_not response_json['success']
    end

    should "return 404 for non-existent source profile" do
      post :copy, params: { id: 9999, name: 'New Profile' }
      assert_response :not_found
    end
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
