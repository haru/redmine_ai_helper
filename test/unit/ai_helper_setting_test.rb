require_relative '../test_helper'

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
      assert @setting.errors[:attachment_max_size_mb].present?
    end

    should "validate integer only when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true
      @setting.attachment_max_size_mb = 1.5
      assert_not @setting.valid?
      assert @setting.errors[:attachment_max_size_mb].present?
    end

    should "be valid with value >= 1 when attachment_send_enabled is true" do
      @setting.attachment_send_enabled = true
      @setting.attachment_max_size_mb = 1
      assert @setting.valid?
    end

    should "skip validation when attachment_send_enabled is false" do
      @setting.attachment_send_enabled = false
      @setting.attachment_max_size_mb = 0
      assert @setting.valid?
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
      assert @setting.attachment_send_enabled?
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
        llm_model: "text-embedding-3-large",
      )
    end

    teardown do
      @vector_profile.destroy if @vector_profile.persisted?
    end

    should "be invalid when use_vector_model_profile is true but vector_model_profile_id is blank" do
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = nil
      assert_not @setting.valid?
      assert @setting.errors[:vector_model_profile_id].present?
    end

    should "be valid when use_vector_model_profile is true and vector_model_profile_id is set" do
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = @vector_profile.id
      assert @setting.valid?
    end

    should "be valid when use_vector_model_profile is false even without vector_model_profile_id" do
      @setting.use_vector_model_profile = false
      @setting.vector_model_profile_id = nil
      assert @setting.valid?
    end
  end

  context "before_save clear_vector_model_profile_id_if_disabled" do
    setup do
      @vector_profile = AiHelperModelProfile.create!(
        name: "Vector Profile",
        access_key: "vec_key",
        llm_type: "OpenAI",
        llm_model: "text-embedding-3-large",
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
      @setting.use_vector_model_profile = true
      @setting.vector_model_profile_id = @vector_profile.id
      @setting.save!
      @setting.reload
      assert_equal @vector_profile.id, @setting.vector_model_profile_id
    end
  end
end
