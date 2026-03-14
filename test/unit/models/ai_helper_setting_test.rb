require_relative "../../test_helper"

class AiHelperSettingTest < ActiveSupport::TestCase
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
      llm_type: RedmineAiHelper::LlmProvider::LLM_OPENAI_COMPATIBLE,
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
        llm_type: RedmineAiHelper::LlmProvider::LLM_ANTHROPIC,
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
      assert @setting.errors[:think_model_profile_id].any?
    end

    should "allow nil think_model_profile_id when use_think_model is false" do
      @setting.use_think_model = false
      @setting.think_model_profile_id = nil
      assert @setting.valid?
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
      assert !@setting.max_tokens
    end

    should "return nil if max_tokens is 0" do
      @setting.model_profile.max_tokens = 0
      @setting.model_profile.save!
      assert !@setting.max_tokens
    end

    should "return value if max_token is setted" do
      @setting.model_profile.max_tokens = 1000
      @setting.model_profile.save!
      assert_equal 1000, @setting.max_tokens
    end
  end
end
