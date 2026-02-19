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
end
