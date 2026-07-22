require_relative "../test_helper"

class AiHelperSettingsControllerTest < ActionController::TestCase
  setup do
    AiHelperSetting.delete_all
    AiHelperModelProfile.delete_all
    @request.session[:user_id] = 1 # Assuming user with ID 1 is an admin

    @model_profile = AiHelperModelProfile.create!(name: "Test Profile", access_key: "test_key", llm_type: "OpenAI", llm_model: "gpt-3.5-turbo")
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

      assert_response :unprocessable_content
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "reject JSON format update without CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    begin
      post :update, params: { ai_helper_setting: { model_profile_id: @model_profile.id }, format: :json }

      assert_response :unprocessable_content
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  should "update attachment_send_enabled to true" do
    post :update, params: { ai_helper_setting: { attachment_send_enabled: "1", attachment_max_size_mb: "5" } }

    assert_redirected_to action: :index
    @ai_helper_setting.reload

    assert_equal true, @ai_helper_setting.attachment_send_enabled
    assert_equal 5, @ai_helper_setting.attachment_max_size_mb
  end

  should "update attachment_max_size_mb" do
    post :update, params: { ai_helper_setting: { attachment_send_enabled: "1", attachment_max_size_mb: "10" } }

    assert_redirected_to action: :index
    @ai_helper_setting.reload

    assert_equal 10, @ai_helper_setting.attachment_max_size_mb
  end

  should "skip attachment_max_size_mb validation when attachment_send_enabled is false" do
    post :update, params: { ai_helper_setting: { attachment_send_enabled: "0", attachment_max_size_mb: "0" } }

    assert_redirected_to action: :index
  end

  context "vector model profile settings" do
    setup do
      @vector_profile = AiHelperModelProfile.create!(
        name: "Vector Profile",
        access_key: "vec_key",
        llm_type: "OpenAI",
        llm_model: "text-embedding-3-large"
      )
    end

    teardown do
      @vector_profile.destroy if @vector_profile.persisted?
    end

    should "save use_vector_model_profile true with valid vector_model_profile_id" do
      post :update, params: { ai_helper_setting: { vector_search_enabled: "1", vector_search_uri: "http://localhost:6333", use_vector_model_profile: "1", vector_model_profile_id: @vector_profile.id } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal true, @ai_helper_setting.use_vector_model_profile
      assert_equal @vector_profile.id, @ai_helper_setting.vector_model_profile_id
    end

    should "not save when use_vector_model_profile true but vector_model_profile_id blank" do
      post :update, params: { ai_helper_setting: { vector_search_enabled: "1", vector_search_uri: "http://localhost:6333", use_vector_model_profile: "1", vector_model_profile_id: "" } }

      assert_response :success
      @ai_helper_setting.reload

      assert_not @ai_helper_setting.use_vector_model_profile
    end

    should "save use_vector_model_profile false and clear vector_model_profile_id" do
      @ai_helper_setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: @vector_profile.id)
      post :update, params: { ai_helper_setting: { use_vector_model_profile: "0", vector_model_profile_id: "" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal false, @ai_helper_setting.use_vector_model_profile
      assert_nil @ai_helper_setting.vector_model_profile_id
    end

    should "render vector model profile checkbox on index" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[use_vector_model_profile]']"
    end
  end

  context "think model settings" do
    setup do
      @think_profile = AiHelperModelProfile.create!(
        name: "Think Profile",
        access_key: "think_key",
        llm_type: "Anthropic",
        llm_model: "claude-3-7-sonnet"
      )
    end

    teardown do
      @think_profile.destroy if @think_profile.persisted?
    end

    should "save use_think_model true with valid think_model_profile_id" do
      post :update, params: { ai_helper_setting: { use_think_model: "1", think_model_profile_id: @think_profile.id } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal true, @ai_helper_setting.use_think_model
      assert_equal @think_profile.id, @ai_helper_setting.think_model_profile_id
    end

    should "not save when use_think_model true but think_model_profile_id blank" do
      post :update, params: { ai_helper_setting: { use_think_model: "1", think_model_profile_id: "" } }

      assert_response :success
      @ai_helper_setting.reload

      assert_not @ai_helper_setting.use_think_model
    end

    should "save use_think_model false regardless of think_model_profile_id" do
      post :update, params: { ai_helper_setting: { use_think_model: "0", think_model_profile_id: "" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal false, @ai_helper_setting.use_think_model
    end

    should "render think model checkbox on index" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[use_think_model]']"
    end
  end

  # ─── MCP server enabled setting (T024) ────────────────────────────────────

  context "mcp_server_enabled setting" do
    should "save mcp_server_enabled true" do
      post :update, params: { ai_helper_setting: { mcp_server_enabled: "1" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal true, @ai_helper_setting.mcp_server_enabled
    end

    should "save mcp_server_enabled false" do
      @ai_helper_setting.update_column(:mcp_server_enabled, true)
      post :update, params: { ai_helper_setting: { mcp_server_enabled: "0" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal false, @ai_helper_setting.mcp_server_enabled
    end

    should "render mcp_server_enabled checkbox on index" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[mcp_server_enabled]']"
    end
  end

  context "vector registration target projects" do
    setup do
      @target_project = Project.create!(name: "Vector Target", identifier: "vector-target-proj")
      @target_project.enable_module!(:ai_helper)
      @other_project = Project.create!(name: "Vector Other", identifier: "vector-other-proj")
      @other_project.enable_module!(:ai_helper)
    end

    teardown do
      @target_project.destroy if @target_project&.persisted?
      @other_project.destroy if @other_project&.persisted?
    end

    should "render register-all checkbox checked and project list hidden on initial render (FR-003)" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[vector_register_all_projects]'][checked=checked]"
      assert_select "#ai-helper-vector-target-projects[style*=?]", "display: none"
    end

    should "list only ai_helper-module projects in the selection UI (FR-005)" do
      get :index

      assert_response :success
      assert_not_nil assigns(:ai_helper_projects)
      assert_includes assigns(:ai_helper_projects), @target_project
    end

    should "save register_all OFF with a selection and restore it (FR-007)" do
      post :update, params: { ai_helper_setting: {
        vector_register_all_projects: "0",
        vector_target_project_ids: [ @target_project.id.to_s ]
      } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload
      assert_equal false, @ai_helper_setting.vector_register_all_projects
      assert_equal [ @target_project.id ], @ai_helper_setting.vector_target_project_ids

      get :index
      assert_select "input[type=checkbox][name='ai_helper_setting[vector_target_project_ids][]'][value=?][checked=checked]", @target_project.id.to_s
    end

    should "preserve previously selected projects when saved with register_all ON (FR-006)" do
      post :update, params: { ai_helper_setting: {
        vector_register_all_projects: "1",
        vector_target_project_ids: [ @target_project.id.to_s ]
      } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload
      assert_equal true, @ai_helper_setting.vector_register_all_projects
      assert_equal [ @target_project.id ], @ai_helper_setting.vector_target_project_ids
    end
  end

  context "send_user_id_enabled setting" do
    should "save send_user_id_enabled true" do
      post :update, params: { ai_helper_setting: { send_user_id_enabled: "1" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal true, @ai_helper_setting.send_user_id_enabled
    end

    should "save send_user_id_enabled false" do
      @ai_helper_setting.update_column(:send_user_id_enabled, true)
      post :update, params: { ai_helper_setting: { send_user_id_enabled: "0" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal false, @ai_helper_setting.send_user_id_enabled
    end

    should "render send_user_id_enabled checkbox on index" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[send_user_id_enabled]']"
    end
  end

  context "read_only_mode setting" do
    should "save read_only_mode true" do
      post :update, params: { ai_helper_setting: { read_only_mode: "1" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal true, @ai_helper_setting.read_only_mode
    end

    should "save read_only_mode false" do
      @ai_helper_setting.update_column(:read_only_mode, true)
      post :update, params: { ai_helper_setting: { read_only_mode: "0" } }

      assert_redirected_to action: :index
      @ai_helper_setting.reload

      assert_equal false, @ai_helper_setting.read_only_mode
    end

    should "render read_only_mode checkbox on index" do
      get :index

      assert_response :success
      assert_select "input[type=checkbox][name='ai_helper_setting[read_only_mode]']"
    end
  end

  context "tabbed settings layout" do
    should "render 3 tab links with general selected by default" do
      get :index

      assert_response :success
      assert_select "a#tab-general.selected"
      assert_select "a#tab-model"
      assert_select "a#tab-vector"
      assert_select "div#tab-content-general"
      assert_select "div#tab-content-model[style*='display:none']"
      assert_select "div#tab-content-vector[style*='display:none']"
    end

    should "fallback to general tab when unknown tab name is passed" do
      get :index, params: { tab: "bogus" }

      assert_response :success
      assert_select "a#tab-general.selected"
    end

    should "render general tab fields in general tab content" do
      get :index

      assert_response :success
      assert_select "div#tab-content-general" do
        assert_select "input[type=checkbox][name='ai_helper_setting[attachment_send_enabled]']"
        assert_select "input[type=number][name='ai_helper_setting[attachment_max_size_mb]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[mcp_server_enabled]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[read_only_mode]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[send_user_id_enabled]']"
        assert_select "textarea[name='ai_helper_setting[additional_instructions]']"
      end
    end

    should "save all tab attributes and redirect with tab param" do
      vector_profile = AiHelperModelProfile.create!(
        name: "Vector Save Profile",
        access_key: "vec_key",
        llm_type: "OpenAI",
        llm_model: "text-embedding-3-large"
      )

      post :update, params: {
        tab: "general",
        ai_helper_setting: {
          attachment_send_enabled: "1",
          attachment_max_size_mb: "10",
          mcp_server_enabled: "1",
          read_only_mode: "0",
          send_user_id_enabled: "0",
          additional_instructions: "test instructions",
          model_profile_id: @model_profile.id.to_s,
          use_think_model: "0",
          think_model_profile_id: "",
          vector_search_enabled: "1",
          vector_search_uri: "http://localhost:6333",
          vector_search_api_key: "test-api-key",
          embedding_model: "text-embedding-3-large",
          dimension: "1536",
          embedding_url: "",
          use_vector_model_profile: "1",
          vector_model_profile_id: vector_profile.id.to_s,
          vector_register_all_projects: "1",
          vector_target_project_ids: []
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "general"
      @ai_helper_setting.reload

      assert_equal 10, @ai_helper_setting.attachment_max_size_mb
      assert_equal true, @ai_helper_setting.attachment_send_enabled
      assert_equal true, @ai_helper_setting.mcp_server_enabled
      assert_equal "test instructions", @ai_helper_setting.additional_instructions
      assert_equal @model_profile.id, @ai_helper_setting.model_profile_id
      assert_equal true, @ai_helper_setting.vector_search_enabled
      assert_equal "http://localhost:6333", @ai_helper_setting.vector_search_uri
      assert_equal true, @ai_helper_setting.use_vector_model_profile
      assert_equal vector_profile.id, @ai_helper_setting.vector_model_profile_id

      vector_profile.destroy if vector_profile.persisted?
    end

    should "show general tab on validation error for attachment_max_size_mb" do
      post :update, params: {
        tab: "general",
        ai_helper_setting: {
          attachment_send_enabled: "1",
          attachment_max_size_mb: "0"
        }
      }

      assert_response :success
      assert_select "a#tab-general.selected"
    end

    should "show model tab when error attribute maps to model tab despite submitting from general tab" do
      post :update, params: {
        tab: "general",
        ai_helper_setting: {
          use_think_model: "1",
          think_model_profile_id: ""
        }
      }

      assert_response :success
      assert_select "a#tab-model.selected"
    end

    should "show vector tab when error attribute maps to vector tab despite submitting from general tab" do
      post :update, params: {
        tab: "general",
        ai_helper_setting: {
          vector_search_enabled: "1",
          vector_search_uri: ""
        }
      }

      assert_response :success
      assert_select "a#tab-vector.selected"
    end

    should "render model tab fields in model tab content only" do
      get :index, params: { tab: "model" }

      assert_response :success
      assert_select "a#tab-model.selected"
      assert_select "div#tab-content-model" do
        assert_select "select[name='ai_helper_setting[model_profile_id]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[use_think_model]']"
        assert_select "select[name='ai_helper_setting[think_model_profile_id]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[mcp_server_enabled]']", { count: 0 }
        assert_select "input[type=checkbox][name='ai_helper_setting[vector_search_enabled]']", { count: 0 }
      end
    end

    should "save from model tab and redirect with tab model" do
      post :update, params: {
        tab: "model",
        ai_helper_setting: {
          model_profile_id: @model_profile.id.to_s,
          use_think_model: "0",
          think_model_profile_id: ""
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "model"
      @ai_helper_setting.reload
      assert_equal @model_profile.id, @ai_helper_setting.model_profile_id
    end

    should "show model tab on validation error for think_model_profile_id" do
      post :update, params: {
        tab: "model",
        ai_helper_setting: {
          use_think_model: "1",
          think_model_profile_id: ""
        }
      }

      assert_response :success
      assert_select "a#tab-model.selected"
    end
  end

  context "vector tab layout" do
    should "render vector tab fields in vector tab content only" do
      get :index, params: { tab: "vector" }

      assert_response :success
      assert_select "a#tab-vector.selected"
      assert_select "div#tab-content-vector" do
        assert_select "input[type=checkbox][name='ai_helper_setting[vector_search_enabled]']"
        assert_select "input[type=text][name='ai_helper_setting[vector_search_uri]']"
        assert_select "input[type=text][name='ai_helper_setting[vector_search_api_key]']"
        assert_select "input[type=text][name='ai_helper_setting[embedding_model]']"
        assert_select "input[type=text][name='ai_helper_setting[dimension]']"
        assert_select "input[type=text][name='ai_helper_setting[embedding_url]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[use_vector_model_profile]']"
        assert_select "select[name='ai_helper_setting[vector_model_profile_id]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[vector_register_all_projects]']"
        assert_select "input[type=checkbox][name='ai_helper_setting[attachment_send_enabled]']", { count: 0 }
        assert_select "input[type=checkbox][name='ai_helper_setting[mcp_server_enabled]']", { count: 0 }
        assert_select "select[name='ai_helper_setting[model_profile_id]']", { count: 0 }
      end
    end

    should "save from vector tab and redirect with tab vector" do
      post :update, params: {
        tab: "vector",
        ai_helper_setting: {
          vector_search_enabled: "1",
          vector_search_uri: "http://localhost:6333",
          vector_search_api_key: "test-key",
          embedding_model: "text-embedding-3-large",
          dimension: "1536",
          use_vector_model_profile: "0",
          vector_model_profile_id: "",
          vector_register_all_projects: "1",
          vector_target_project_ids: []
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "vector"
      @ai_helper_setting.reload
      assert_equal "http://localhost:6333", @ai_helper_setting.vector_search_uri
    end

    should "show vector tab on validation error for vector_search_uri" do
      post :update, params: {
        tab: "vector",
        ai_helper_setting: {
          vector_search_enabled: "1",
          vector_search_uri: ""
        }
      }

      assert_response :success
      assert_select "a#tab-vector.selected"
    end
  end

  context "tab param handling" do
    should "omit tab param on redirect when tab is blank" do
      post :update, params: { tab: "", ai_helper_setting: { model_profile_id: @model_profile.id } }

      assert_response :redirect
      assert_no_match(/[?&]tab=/, @response.redirect_url)
    end

    should "keep tab param on redirect when tab is present" do
      post :update, params: { tab: "model", ai_helper_setting: { model_profile_id: @model_profile.id } }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "model"
    end

    should "treat blank tab param as nil on index" do
      get :index, params: { tab: "" }

      assert_response :success
      assert_nil assigns(:selected_tab)
    end

    should "bind hidden tab field to selected tab on validation error" do
      post :update, params: {
        tab: "general",
        ai_helper_setting: {
          vector_search_enabled: "1",
          vector_search_uri: ""
        }
      }

      assert_response :success
      assert_select "input[type=hidden][name=tab][value=vector]"
    end
  end

  # Test-only chat adapter registered for the channels tab tests, so the tab
  # UI can be verified without depending on any concrete adapter.
  class FakeUiAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    class << self
      def channel_type
        "ui_chat"
      end

      def required_setting_fields
        [ :bot_token ]
      end
    end
  end

  class FakeOtherAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    class << self
      def channel_type
        "fake_other"
      end

      def required_setting_fields
        [ :bot_token ]
      end
    end
  end

  context "channels tab" do
    setup do
      AiHelperChatAdapterSetting.delete_all
      AiHelperChannelBinding.delete_all
    end

    should "render the channels tab link" do
      get :index

      assert_response :success
      assert_select ".tabs a#tab-channels"
    end

    should "render a settings section for each registered adapter" do
      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#tab-content-channels input[name='chat_adapter_settings[ui_chat][enabled]']"
      assert_select "#tab-content-channels input[name='chat_adapter_settings[ui_chat][bot_token]'][type=password]"
      assert_select "#tab-content-channels select[name='chat_adapter_settings[ui_chat][dm_default_project_id]']"
      assert_select "#tab-content-channels input[name='chat_adapter_settings[ui_chat][redmine_user_id]'][type=hidden]"
      assert_select "#tab-content-channels input[name='chat_adapter_settings[ui_chat][redmine_user_name]'][type=text]"
    end

    should "save adapter settings from the channels tab" do
      post :update, params: {
        tab: "channels",
        ai_helper_setting: { additional_instructions: "keep" },
        chat_adapter_settings: {
          "ui_chat" => { "enabled" => "1", "bot_token" => "xoxb-ui", "dm_default_project_id" => "1", "redmine_user_id" => "2" }
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      setting = AiHelperChatAdapterSetting.for_channel("ui_chat")
      assert setting.enabled
      assert_equal "xoxb-ui", setting.bot_token
      assert_equal 1, setting.dm_default_project_id
      assert_equal 2, setting.redmine_user_id
    end

    should "re-render the channels tab when adapter settings are invalid" do
      post :update, params: {
        tab: "general",
        ai_helper_setting: {},
        chat_adapter_settings: {
          "ui_chat" => { "enabled" => "1", "bot_token" => "" }
        }
      }

      assert_response :success
      assert_equal "channels", assigns(:selected_tab)
      assert_not AiHelperChatAdapterSetting.enabled?("ui_chat")
    end

    should "list existing channel bindings in the channels tab" do
      AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)
      AiHelperChannelBinding.create!(channel_type: "ui_chat", channel_id: "C111", channel_name: "#dev", project: Project.find(1))

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#tab-content-channels", text: /C111/
      assert_select "#tab-content-channels", text: /#dev/
    end

    should "not render the channel bindings form when the adapter setting is not persisted" do
      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#adapter-bindings-ui_chat", count: 0
    end

    should "not render the channel bindings form when a required token is blank" do
      AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "", redmine_user_id: 2)

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#adapter-bindings-ui_chat", count: 0
    end

    should "not render the channel bindings form when the execution account is blank" do
      AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: nil)

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#adapter-bindings-ui_chat", count: 0
    end

    should "render the channel bindings form when the adapter setting is configured" do
      AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#adapter-bindings-ui_chat"
      assert_select "#tab-content-channels input[name='ai_helper_channel_binding[channel_id]']"
    end

    should "not render the raw app or bot token value in the HTML source" do
      AiHelperChatAdapterSetting.create!(
        channel_type: "ui_chat", enabled: true, bot_token: "xoxb-supersecret-value", redmine_user_id: 2
      )

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_no_match(/xoxb-supersecret-value/, @response.body)
      assert_select "#tab-content-channels input[name='chat_adapter_settings[ui_chat][bot_token]'][value=?]",
                    AiHelperSettingsController::DUMMY_TOKEN
    end

    should "render the masked token next to the field when a token is stored" do
      AiHelperChatAdapterSetting.create!(
        channel_type: "ui_chat", enabled: true, bot_token: "xoxb-supersecret-value", redmine_user_id: 2
      )

      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#tab-content-channels em.info", text: /xoxb\*+/
    end

    should "preserve the stored token when the dummy value is submitted unchanged" do
      AiHelperChatAdapterSetting.create!(
        channel_type: "ui_chat", enabled: true, bot_token: "xoxb-original", redmine_user_id: 2
      )

      post :update, params: {
        tab: "channels",
        ai_helper_setting: {},
        chat_adapter_settings: {
          "ui_chat" => { "enabled" => "1", "bot_token" => AiHelperSettingsController::DUMMY_TOKEN }
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      assert_equal "xoxb-original", AiHelperChatAdapterSetting.for_channel("ui_chat").bot_token
    end

    should "roll back adapter settings when the global setting is invalid" do
      existing = AiHelperChatAdapterSetting.create!(
        channel_type: "ui_chat", enabled: false, bot_token: "xoxb-old"
      )

      post :update, params: {
        tab: "general",
        ai_helper_setting: { attachment_send_enabled: "1", attachment_max_size_mb: "0" },
        chat_adapter_settings: {
          "ui_chat" => { "enabled" => "1", "bot_token" => "xoxb-new" }
        }
      }

      assert_response :success
      existing.reload
      assert_not existing.enabled, "adapter must not be partially persisted when the global setting is invalid"
      assert_equal "xoxb-old", existing.bot_token
    end

    context "US1: adapter enabled checkbox toggle visibility" do
      should "render adapter-settings div wrapping settings fields when enabled" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: true, bot_token: "xoxb-test", redmine_user_id: 2)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#adapter-settings-ui_chat"
        assert_select ".adapter-enabled-checkbox[data-adapter-type=ui_chat]"
      end

      should "render adapter-settings div even when adapter is disabled" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#adapter-settings-ui_chat"
      end

      should "render adapter-bindings fieldset with an id so JS can toggle it alongside adapter-settings" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: true, bot_token: "xoxb-test", redmine_user_id: 2)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#adapter-bindings-ui_chat"
      end

      should "save adapter settings correctly when adapter is disabled" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-keep")

        post :update, params: {
          tab: "channels",
          ai_helper_setting: {},
          chat_adapter_settings: {
            "ui_chat" => { "enabled" => "0", "bot_token" => AiHelperSettingsController::DUMMY_TOKEN }
          }
        }

        assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
        setting = AiHelperChatAdapterSetting.for_channel("ui_chat")
        assert_not setting.enabled
        assert_equal "xoxb-keep", setting.bot_token
      end
    end

    context "US2: incremental search account selection" do
      should "render text input with datalist for redmine_user instead of select" do
        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels input[type=text][name='chat_adapter_settings[ui_chat][redmine_user_name]']"
        assert_select "#tab-content-channels select[name='chat_adapter_settings[ui_chat][redmine_user_id]']", { count: 0 }
      end

      should "render hidden input for redmine_user_id and datalist with options" do
        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels input[type=hidden][name='chat_adapter_settings[ui_chat][redmine_user_id]']"
        assert_select "#tab-content-channels datalist#ai-helper-users-datalist-ui_chat option", { minimum: 1 }
      end

      should "render datalist option value as the user name with the user id in a data attribute" do
        user = User.active.sorted.first

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels datalist#ai-helper-users-datalist-ui_chat option[value=?][data-user-id=?]",
                      user.name, user.id.to_s
      end

      should "display selected user name in text input on page reload when redmine_user_id is set" do
        user = User.active.sorted.first
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: true, bot_token: "xoxb-test", redmine_user_id: user.id)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "input[type=text][name='chat_adapter_settings[ui_chat][redmine_user_name]'][value=?]", user.name
        assert_select "input[type=hidden][name='chat_adapter_settings[ui_chat][redmine_user_id]'][value=?]", user.id.to_s
      end

      should "save datalist-selected user_id correctly" do
        user = User.active.sorted.first

        post :update, params: {
          tab: "channels",
          ai_helper_setting: {},
          chat_adapter_settings: {
            "ui_chat" => { "enabled" => "1", "bot_token" => "xoxb-new", "redmine_user_id" => user.id.to_s, "redmine_user_name" => user.name }
          }
        }

        assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
        setting = AiHelperChatAdapterSetting.for_channel("ui_chat")
        assert_equal user.id, setting.redmine_user_id
      end
    end

    context "US3: channel bindings inside adapter" do
      should "render channel bindings table inside each adapter fieldset" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)
        AiHelperChannelBinding.create!(channel_type: "ui_chat", channel_id: "C111", channel_name: "#dev", project: Project.find(1))

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels fieldset.box.tabular" do
          assert_select "fieldset.box table.list td", text: "C111"
        end
      end

      should "not render chat tool selector dropdown in channels tab" do
        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "select[name='ai_helper_channel_binding[channel_type]']", { count: 0 }
      end

      should "not render channel type column in bindings table" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)
        AiHelperChannelBinding.create!(channel_type: "ui_chat", channel_id: "C111", channel_name: "#dev", project: Project.find(1))

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels fieldset.box.tabular table.list thead th", { count: 4 }
      end

      should "render hidden field with channel_type in the add binding form" do
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "input[type=hidden][name='ai_helper_channel_binding[channel_type]'][value='ui_chat']"
      end

      should "filter bindings by channel_type" do
        slack_project = Project.create!(name: "Slack Proj", identifier: "slack-proj")
        slack_project.enable_module!(:ai_helper)
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: false, bot_token: "xoxb-ui", redmine_user_id: 2)
        AiHelperChatAdapterSetting.create!(channel_type: "fake_other", enabled: false, bot_token: "xoxb-other", redmine_user_id: 2)
        AiHelperChannelBinding.create!(channel_type: "ui_chat", channel_id: "C111", channel_name: "#dev", project: Project.find(1))
        AiHelperChannelBinding.create!(channel_type: "fake_other", channel_id: "S222", channel_name: "#general", project: slack_project)

        get :index, params: { tab: "channels" }

        assert_response :success
        assert_select "#tab-content-channels", text: /C111/
        assert_select "#tab-content-channels", text: /S222/
        slack_project.destroy
      end

      should "clear redmine_user_id when both name and id are blank and the adapter is disabled" do
        user = User.active.sorted.first
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: true, bot_token: "xoxb-test", redmine_user_id: user.id)

        post :update, params: {
          tab: "channels",
          ai_helper_setting: {},
          chat_adapter_settings: {
            "ui_chat" => { "enabled" => "0", "bot_token" => "xoxb-test", "redmine_user_id" => "", "redmine_user_name" => "" }
          }
        }

        assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
        setting = AiHelperChatAdapterSetting.for_channel("ui_chat")
        assert_nil setting.redmine_user_id
      end

      should "reject clearing redmine_user_id while the adapter stays enabled" do
        user = User.active.sorted.first
        AiHelperChatAdapterSetting.create!(channel_type: "ui_chat", enabled: true, bot_token: "xoxb-test", redmine_user_id: user.id)

        post :update, params: {
          tab: "channels",
          ai_helper_setting: {},
          chat_adapter_settings: {
            "ui_chat" => { "enabled" => "1", "bot_token" => "xoxb-test", "redmine_user_id" => "", "redmine_user_name" => "" }
          }
        }

        assert_response :success
        assert_equal "channels", assigns(:selected_tab)
        setting = AiHelperChatAdapterSetting.for_channel("ui_chat")
        assert_equal user.id, setting.redmine_user_id
      end

      should "reject non-matching redmine_user_name with validation error" do
        post :update, params: {
          tab: "channels",
          ai_helper_setting: {},
          chat_adapter_settings: {
            "ui_chat" => { "enabled" => "1", "bot_token" => "xoxb-test", "redmine_user_id" => "", "redmine_user_name" => "nonexistent user" }
          }
        }

        assert_response :success
        assert_equal "channels", assigns(:selected_tab)
        assert_select "#errorExplanation", text: /does not match any user/
      end
    end
  end

  # Discord adapter is auto-registered via the init.rb glob, so the existing
  # settings controller handles its row with no controller changes (US1).
  context "discord adapter channel settings" do
    setup do
      AiHelperChatAdapterSetting.delete_all
      AiHelperChannelBinding.delete_all
      @user = User.active.sorted.first
    end

    should "render only the bot token field for discord (required_setting_fields driven)" do
      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#tab-content-channels input[name='chat_adapter_settings[discord][bot_token]'][type=password]"
      assert_select "#tab-content-channels input[name='chat_adapter_settings[discord][app_token]']", { count: 0 }
    end

    should "render both token fields for slack (app_token and bot_token)" do
      get :index, params: { tab: "channels" }

      assert_response :success
      assert_select "#tab-content-channels input[name='chat_adapter_settings[slack][app_token]'][type=password]"
      assert_select "#tab-content-channels input[name='chat_adapter_settings[slack][bot_token]'][type=password]"
    end

    should "save a discord settings row without an app token" do
      post :update, params: {
        tab: "channels",
        ai_helper_setting: {},
        chat_adapter_settings: {
          "discord" => { "enabled" => "1", "bot_token" => "discord-bot-xyz",
                         "redmine_user_id" => @user.id.to_s, "redmine_user_name" => @user.name,
                         "dm_default_project_id" => "1" }
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      setting = AiHelperChatAdapterSetting.for_channel("discord")
      assert setting.enabled
      assert_equal "discord-bot-xyz", setting.bot_token
      assert_equal @user.id, setting.redmine_user_id
      assert_equal 1, setting.dm_default_project_id
    end

    should "reject enabling discord without a bot token" do
      post :update, params: {
        tab: "channels",
        ai_helper_setting: {},
        chat_adapter_settings: {
          "discord" => { "enabled" => "1", "bot_token" => "" }
        }
      }

      assert_response :success
      assert_equal "channels", assigns(:selected_tab)
      assert_not AiHelperChatAdapterSetting.enabled?("discord")
    end
  end

  context "help action" do
    should "return HTML for a valid channel type" do
      get :help, params: { channel_type: "discord" }

      assert_response :success
      assert_equal "text/html", @response.media_type
      assert @response.body.include?("Discord Gateway Setup Guide")
    end

    should "return HTML for slack" do
      get :help, params: { channel_type: "slack" }

      assert_response :success
      assert @response.body.include?("Slack Gateway Setup Guide")
    end

    should "return 404 for an invalid channel type" do
      get :help, params: { channel_type: "unknown" }

      assert_response :not_found
    end
  end
end
