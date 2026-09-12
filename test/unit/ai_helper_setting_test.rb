require_relative "../test_helper"

class AiHelperSettingTest < ActiveSupport::TestCase
  setup do
    AiHelperSetting.delete_all
    @setting = AiHelperSetting.find_or_create
  end

  context "attachment_send_enabled" do
    should "default to false" do
      assert_equal false, @setting.attachment_send_enabled
    end

    should "be settable to true" do
      @setting.attachment_send_enabled = true
      @setting.save!
      @setting.reload

      assert_equal true, @setting.attachment_send_enabled
    end
  end

  context "attachment_max_size_mb" do
    should "default to 3" do
      assert_equal 3, @setting.attachment_max_size_mb
    end

    should "validate numericality when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true
      @setting.attachment_max_size_mb = 0

      assert_not @setting.valid?
      assert_predicate @setting.errors[:attachment_max_size_mb], :present?
    end

    should "validate integer only when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true
      @setting.attachment_max_size_mb = 1.5

      assert_not @setting.valid?
      assert_predicate @setting.errors[:attachment_max_size_mb], :present?
    end

    should "be valid with value >= 1 when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true
      @setting.attachment_max_size_mb = 1

      assert_predicate @setting, :valid?
    end

    should "skip validation when attachment_send_enabled is false" do
      @setting.attachment_send_enabled = false
      @setting.attachment_max_size_mb = 0

      assert_predicate @setting, :valid?
    end
  end

  context "class method attachment_send_enabled?" do
    should "return false when setting is disabled" do
      @setting.update!(attachment_send_enabled: false)

      assert_equal false, AiHelperSetting.attachment_send_enabled?
    end

    should "return true when setting is enabled" do
      @setting.update!(attachment_send_enabled: true)

      assert_equal true, AiHelperSetting.attachment_send_enabled?
    end
  end

  context "class method attachment_max_size_mb" do
    should "return the configured value" do
      @setting.update!(attachment_send_enabled: true, attachment_max_size_mb: 5)

      assert_equal 5, AiHelperSetting.attachment_max_size_mb
    end

    should "return default value" do
      assert_equal 3, AiHelperSetting.attachment_max_size_mb
    end
  end

  context "instance method attachment_send_enabled?" do
    should "return true when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true

      assert_predicate @setting, :attachment_send_enabled?
    end

    should "return false when attachment_send_enabled is false" do
      @setting.attachment_send_enabled = false

      assert_not @setting.attachment_send_enabled?
    end
  end

  context "use_vector_model_profile validation" do
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

    should "be invalid when use_vector_model_profile is true, vector_search_enabled is true, but vector_model_profile_id is blank" do
      @setting.vector_search_enabled = true
      @setting.vector_search_uri = "http://localhost:6333"
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = nil

      assert_not @setting.valid?
      assert_predicate @setting.errors[:vector_model_profile_id], :present?
    end

    should "be valid when use_vector_model_profile is true, vector_search_enabled is true, and vector_model_profile_id is set" do
      @setting.vector_search_enabled = true
      @setting.vector_search_uri = "http://localhost:6333"
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = @vector_profile.id

      assert_predicate @setting, :valid?
    end

    should "be valid when use_vector_model_profile is false even without vector_model_profile_id" do
      @setting.use_vector_model_profile = false
      @setting.vector_model_profile_id = nil

      assert_predicate @setting, :valid?
    end

    should "skip vector_model_profile_id validation when vector_search_enabled is false" do
      @setting.vector_search_enabled = false
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = nil

      assert_predicate @setting, :valid?
    end
  end

  context "before_save clear_vector_model_profile_id_if_disabled" do
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

    should "clear vector_model_profile_id when use_vector_model_profile is set to false" do
      @setting.update_columns(use_vector_model_profile: true, vector_model_profile_id: @vector_profile.id)
      @setting.reload
      @setting.use_vector_model_profile = false
      @setting.save!
      @setting.reload

      assert_nil @setting.vector_model_profile_id
    end

    should "not clear vector_model_profile_id when use_vector_model_profile is true" do
      @setting.vector_search_enabled = true
      @setting.vector_search_uri = "http://localhost:6333"
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = @vector_profile.id
      @setting.save!
      @setting.reload

      assert_equal @vector_profile.id, @setting.vector_model_profile_id
    end

    should "clear use_vector_model_profile and vector_model_profile_id when vector_search_enabled is set to false" do
      @setting.update_columns(
        vector_search_enabled: true,
        use_vector_model_profile: true,
        vector_model_profile_id: @vector_profile.id
      )
      @setting.reload
      @setting.vector_search_enabled = false
      @setting.save!
      @setting.reload

      assert_equal false, @setting.use_vector_model_profile
      assert_nil @setting.vector_model_profile_id
    end
  end

  # ─── mcp_server_enabled (T025) ────────────────────────────────────────────

  context "mcp_server_enabled" do
    should "default to false" do
      assert_equal false, @setting.mcp_server_enabled
    end

    should "be readable and writable" do
      @setting.mcp_server_enabled = true
      @setting.save!
      @setting.reload

      assert_equal true, @setting.mcp_server_enabled
    end

    should "be settable to false" do
      @setting.update_column(:mcp_server_enabled, true)
      @setting.mcp_server_enabled = false
      @setting.save!
      @setting.reload

      assert_equal false, @setting.mcp_server_enabled
    end
  end

  context "class method mcp_server_enabled?" do
    should "return false when mcp_server_enabled is false" do
      @setting.update!(mcp_server_enabled: false)

      assert_equal false, AiHelperSetting.mcp_server_enabled?
    end

    should "return true when mcp_server_enabled is true" do
      @setting.update!(mcp_server_enabled: true)

      assert_equal true, AiHelperSetting.mcp_server_enabled?
    end
  end

  # ─── send_user_id_enabled ────────────────────────────────────────────

  context "send_user_id_enabled" do
    should "default to false" do
      assert_equal false, @setting.send_user_id_enabled
    end

    should "be readable and writable" do
      @setting.send_user_id_enabled = true
      @setting.save!
      @setting.reload

      assert_equal true, @setting.send_user_id_enabled
    end

    should "be settable to false" do
      @setting.update_column(:send_user_id_enabled, true)
      @setting.send_user_id_enabled = false
      @setting.save!
      @setting.reload

      assert_equal false, @setting.send_user_id_enabled
    end
  end

  context "class method send_user_id_enabled?" do
    should "return false when send_user_id_enabled is false" do
      @setting.update!(send_user_id_enabled: false)

      assert_equal false, AiHelperSetting.send_user_id_enabled?
    end

    should "return true when send_user_id_enabled is true" do
      @setting.update!(send_user_id_enabled: true)

      assert_equal true, AiHelperSetting.send_user_id_enabled?
    end
  end

  # ─── read_only_mode ────────────────────────────────────────────

  context "read_only_mode" do
    should "default to false" do
      assert_equal false, @setting.read_only_mode
    end
  end

  context "class method read_only_mode?" do
    should "return false when read_only_mode is false" do
      @setting.update!(read_only_mode: false)

      assert_equal false, AiHelperSetting.read_only_mode?
    end

    should "return true when read_only_mode is true" do
      @setting.update!(read_only_mode: true)

      assert_equal true, AiHelperSetting.read_only_mode?
    end
  end

  # ─── vector scope and all_projects_scope ───────────────────────

  context "vector_scope_projects with all_projects_scope" do
    fixtures :projects, :enabled_modules

    should "limit to ai_helper module-enabled projects when all_projects_scope is OFF" do
      @setting.update_column(:all_projects_scope, false)
      project = Project.find(3)
      project.enable_module!(:ai_helper)

      ids = @setting.vector_scope_projects.map(&:id)

      assert_includes ids, project.id
      assert_not_includes ids, Project.find(4).id # module-disabled project
    end

    should "include module-disabled projects when all_projects_scope is ON (FR-016)" do
      @setting.update_column(:all_projects_scope, true)

      ids = @setting.vector_scope_projects.map(&:id)

      assert_includes ids, Project.find(3).id
      assert_includes ids, Project.find(4).id
    end

    should "exclude archived projects when all_projects_scope is ON" do
      @setting.update_column(:all_projects_scope, true)
      project = Project.find(3)
      project.update_column(:status, Project::STATUS_ARCHIVED)

      assert_not_includes @setting.vector_scope_projects.map(&:id), project.id
    ensure
      project.update_column(:status, Project::STATUS_ACTIVE)
    end

    should "keep closed projects in scope when all_projects_scope is ON" do
      @setting.update_column(:all_projects_scope, true)
      project = Project.find(3)
      project.update_column(:status, Project::STATUS_CLOSED)

      assert_includes @setting.vector_scope_projects.map(&:id), project.id
    ensure
      project.update_column(:status, Project::STATUS_ACTIVE)
    end

    should "exclude projects scheduled for deletion when all_projects_scope is ON" do
      @setting.update_column(:all_projects_scope, true)
      project = Project.find(3)
      project.update_column(:status, Project::STATUS_SCHEDULED_FOR_DELETION)

      assert_not_includes @setting.vector_scope_projects.map(&:id), project.id
    ensure
      project.update_column(:status, Project::STATUS_ACTIVE)
    end
  end

  context "vector_target? project status" do
    fixtures :projects, :enabled_modules

    should "reject a project scheduled for deletion when all_projects_scope is ON" do
      @setting.update_column(:all_projects_scope, true)
      @setting.update_column(:vector_register_all_projects, true)
      project = Project.find(3)
      project.update_column(:status, Project::STATUS_SCHEDULED_FOR_DELETION)

      assert_equal false, @setting.vector_target?(project)
    ensure
      project.update_column(:status, Project::STATUS_ACTIVE)
    end

    should "accept an active project when all_projects_scope is ON" do
      @setting.update_column(:all_projects_scope, true)
      @setting.update_column(:vector_register_all_projects, true)

      assert_equal true, @setting.vector_target?(Project.find(3))
    end
  end

  context "vector_search_enabled_for? with all_projects_scope" do
    fixtures :projects, :enabled_modules

    should "return true for a module-disabled project when all_projects_scope and register_all are ON" do
      @setting.update!(vector_search_enabled: true, vector_search_uri: "http://qdrant.example:6333")
      @setting.update_column(:all_projects_scope, true)
      @setting.update_column(:vector_register_all_projects, true)

      assert_equal true, AiHelperSetting.vector_search_enabled_for?(Project.find(3))
    end

    should "return false for a module-disabled project when all_projects_scope is OFF" do
      @setting.update!(vector_search_enabled: true, vector_search_uri: "http://qdrant.example:6333")
      @setting.update_column(:all_projects_scope, false)
      @setting.update_column(:vector_register_all_projects, true)

      assert_equal false, AiHelperSetting.vector_search_enabled_for?(Project.find(3))
    end
  end
end
