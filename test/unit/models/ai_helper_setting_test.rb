require_relative "../../test_helper"

class AiHelperSettingTest < ActiveSupport::TestCase
  fixtures :projects, :enabled_modules

  # Setup method to create a default setting before each test
  setup do
    AiHelperSetting.destroy_all
    @setting = AiHelperSetting.setting
    model_profile = AiHelperModelProfile.create!(
      name: "Default Model Profile",
      llm_model: "gpt-3.5-turbo",
      access_key: "test_access_key",
      temperature: 0.7,
      base_uri: "https://api.openai.com/v1",
      max_tokens: 2048,
      llm_type: RedmineAiHelper::LlmProvider::LLM_OPENAI_COMPATIBLE
    )
    @setting.model_profile = model_profile
  end

  teardown do
    AiHelperSetting.destroy_all
  end

  context "think model" do
    setup do
      @think_profile = AiHelperModelProfile.create!(
        name: "Think Model Profile",
        llm_model: "claude-3-7-sonnet",
        access_key: "think_access_key",
        temperature: 0.7,
        base_uri: "https://api.anthropic.com",
        max_tokens: 4096,
        llm_type: RedmineAiHelper::LlmProvider::LLM_ANTHROPIC
      )
    end

    teardown do
      @think_profile.destroy if @think_profile.persisted?
    end

    should "default use_think_model to false" do
      assert_equal false, @setting.use_think_model
    end

    should "validate presence of think_model_profile_id when use_think_model is true" do
      @setting.use_think_model = true
      @setting.think_model_profile_id = nil

      assert_not @setting.valid?
      assert_predicate @setting.errors[:think_model_profile_id], :any?
    end

    should "allow nil think_model_profile_id when use_think_model is false" do
      @setting.use_think_model = false
      @setting.think_model_profile_id = nil

      assert_predicate @setting, :valid?
    end

    should "resolve belongs_to association for think_model_profile" do
      @setting.use_think_model = true
      @setting.think_model_profile = @think_profile
      @setting.save!
      @setting.reload

      assert_equal @think_profile, @setting.think_model_profile
      assert_instance_of AiHelperModelProfile, @setting.think_model_profile
    end
  end

  context "max_tokens" do
    should "return nil if not set" do
      @setting.model_profile.max_tokens = nil
      @setting.model_profile.save!

      assert_not @setting.max_tokens
    end

    should "return nil if max_tokens is 0" do
      @setting.model_profile.max_tokens = 0
      @setting.model_profile.save!

      assert_not @setting.max_tokens
    end

    should "return value if max_token is setted" do
      @setting.model_profile.max_tokens = 1000
      @setting.model_profile.save!

      assert_equal 1000, @setting.max_tokens
    end
  end

  context "vector registration target selection" do
    setup do
      # project_a / project_b have ai_helper enabled; project_c does not.
      @project_a = Project.find(1)
      @project_b = Project.find(2)
      @project_c = Project.find(3)
      [ @project_a, @project_b, @project_c ].each do |p|
        p.enabled_modules.where(name: "ai_helper").destroy_all
      end
      @project_a.enabled_modules.create!(name: "ai_helper")
      @project_b.enabled_modules.create!(name: "ai_helper")
      @setting.vector_search_uri = "http://localhost:6333"
      @setting.save!
    end

    should "default vector_register_all_projects to true" do
      assert_equal true, @setting.vector_register_all_projects
    end

    context "vector_target_projects_relation" do
      should "return all ai_helper-module projects when register_all is ON" do
        @setting.update!(vector_register_all_projects: true)
        ids = @setting.vector_target_projects_relation.pluck(:id)
        assert_includes ids, @project_a.id
        assert_includes ids, @project_b.id
        assert_not_includes ids, @project_c.id
      end

      should "return intersection of selection and ai_helper-module projects when OFF" do
        @setting.update!(vector_register_all_projects: false, vector_target_project_ids: [ @project_a.id, @project_c.id ])
        ids = @setting.vector_target_projects_relation.pluck(:id)
        assert_equal [ @project_a.id ], ids
      end

      should "return empty relation when OFF with no selection (FR-014)" do
        @setting.update!(vector_register_all_projects: false, vector_target_project_ids: [])
        assert_empty @setting.vector_target_projects_relation.to_a
      end
    end

    context "vector_target?" do
      should "return false for nil project" do
        assert_equal false, @setting.vector_target?(nil)
      end

      should "return false when project module disabled even if register_all ON" do
        @setting.update!(vector_register_all_projects: true)
        assert_equal false, @setting.vector_target?(@project_c)
      end

      should "return true for module-enabled project when register_all ON" do
        @setting.update!(vector_register_all_projects: true)
        assert_equal true, @setting.vector_target?(@project_a)
      end

      should "return true only for selected module-enabled projects when OFF" do
        @setting.update!(vector_register_all_projects: false, vector_target_project_ids: [ @project_a.id ])
        assert_equal true, @setting.vector_target?(@project_a)
        assert_equal false, @setting.vector_target?(@project_b)
      end
    end

    context "self.vector_search_enabled_for?" do
      should "return false when vector_search_enabled is false" do
        @setting.update!(vector_search_enabled: false, vector_register_all_projects: true)
        assert_equal false, AiHelperSetting.vector_search_enabled_for?(@project_a)
      end

      should "return true for any module-enabled project when enabled and register_all ON" do
        @setting.update!(vector_search_enabled: true, vector_register_all_projects: true)
        AiHelperSetting.stubs(:setting).returns(@setting)
        assert_equal true, AiHelperSetting.vector_search_enabled_for?(@project_a)
      end

      should "return false for a module-disabled project even when register_all ON (matches registration scope)" do
        @setting.update!(vector_search_enabled: true, vector_register_all_projects: true)
        AiHelperSetting.stubs(:setting).returns(@setting)
        assert_equal false, AiHelperSetting.vector_search_enabled_for?(@project_c)
      end

      should "honor selection when enabled and register_all OFF" do
        @setting.update!(vector_search_enabled: true, vector_register_all_projects: false, vector_target_project_ids: [ @project_a.id ])
        AiHelperSetting.stubs(:setting).returns(@setting)
        assert_equal true, AiHelperSetting.vector_search_enabled_for?(@project_a)
        assert_equal false, AiHelperSetting.vector_search_enabled_for?(@project_b)
      end

      should "return false for all projects when OFF with empty selection (FR-014)" do
        @setting.update!(vector_search_enabled: true, vector_register_all_projects: false, vector_target_project_ids: [])
        AiHelperSetting.stubs(:setting).returns(@setting)
        assert_equal false, AiHelperSetting.vector_search_enabled_for?(@project_a)
      end
    end

    context "selection preservation across ON/OFF (FR-006)" do
      should "preserve selected ids when saved with register_all ON" do
        @setting.update!(vector_register_all_projects: false, vector_target_project_ids: [ @project_a.id ])
        @setting.update!(vector_register_all_projects: true)
        @setting.reload
        assert_equal [ @project_a.id ], @setting.vector_target_project_ids
      end
    end
  end
end
