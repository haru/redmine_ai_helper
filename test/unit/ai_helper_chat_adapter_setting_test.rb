# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperChatAdapterSettingTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  fixtures :projects, :users

  # Test-only adapter declaring required setting fields, used to verify the
  # enable-time validation contract without depending on the Slack adapter.
  class FakeSettingAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    class << self
      def channel_type
        "fake_setting_chat"
      end

      def required_setting_fields
        [ :app_token, :bot_token ]
      end
    end
  end

  context "validations" do
    should "require channel_type" do
      setting = AiHelperChatAdapterSetting.new

      assert_not setting.valid?
      assert_predicate setting.errors[:channel_type], :present?
    end

    should "reject a duplicate channel_type" do
      create(:ai_helper_chat_adapter_setting, channel_type: "slack")
      duplicate = build(:ai_helper_chat_adapter_setting, channel_type: "slack")

      assert_not duplicate.valid?
      assert_predicate duplicate.errors[:channel_type], :present?
    end

    should "require the adapter's required fields when enabled" do
      setting = AiHelperChatAdapterSetting.new(channel_type: "fake_setting_chat", enabled: true)

      assert_not setting.valid?
      assert_predicate setting.errors[:app_token], :present?
      assert_predicate setting.errors[:bot_token], :present?
    end

    should "be valid when enabled with all required fields present" do
      setting = AiHelperChatAdapterSetting.new(
        channel_type: "fake_setting_chat", enabled: true,
        app_token: "xapp-test", bot_token: "xoxb-test"
      )

      assert_predicate setting, :valid?
    end

    should "not require adapter fields when disabled" do
      setting = AiHelperChatAdapterSetting.new(channel_type: "fake_setting_chat", enabled: false)

      assert_predicate setting, :valid?
    end
  end

  context "safe_attributes" do
    should "accept enabled, tokens, dm_default_project_id and redmine_user_id" do
      setting = create(:ai_helper_chat_adapter_setting)
      setting.safe_attributes = {
        "enabled" => "1",
        "app_token" => "xapp-abc",
        "bot_token" => "xoxb-abc",
        "dm_default_project_id" => "1",
        "redmine_user_id" => "2"
      }

      assert setting.enabled
      assert_equal "xapp-abc", setting.app_token
      assert_equal "xoxb-abc", setting.bot_token
      assert_equal 1, setting.dm_default_project_id
      assert_equal 2, setting.redmine_user_id
    end

    should "not allow changing channel_type" do
      setting = create(:ai_helper_chat_adapter_setting)
      setting.safe_attributes = { "channel_type" => "discord" }

      assert_equal "slack", setting.channel_type
    end
  end

  context "for_channel" do
    should "return the persisted setting when it exists" do
      setting = create(:ai_helper_chat_adapter_setting)

      assert_equal setting, AiHelperChatAdapterSetting.for_channel("slack")
    end

    should "return a new record for an unknown channel_type" do
      setting = AiHelperChatAdapterSetting.for_channel("unknown_chat")

      assert_predicate setting, :new_record?
      assert_equal "unknown_chat", setting.channel_type
    end
  end

  context "class method enabled?" do
    should "return true when the setting row is enabled" do
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_setting_chat", enabled: true, app_token: "xapp-a", bot_token: "xoxb-b")

      assert AiHelperChatAdapterSetting.enabled?("fake_setting_chat")
    end

    should "return false when no setting row exists" do
      assert_not AiHelperChatAdapterSetting.enabled?("missing_chat")
    end
  end

  context "dm_default_project" do
    should "return the associated project" do
      setting = create(:ai_helper_chat_adapter_setting, dm_default_project_id: 1)

      assert_equal Project.find(1), setting.dm_default_project
    end
  end

  context "service_account" do
    should "return the configured active user" do
      setting = create(:ai_helper_chat_adapter_setting, redmine_user_id: 2)

      assert_equal User.find(2), setting.service_account
    end

    should "return nil when no user is configured" do
      setting = create(:ai_helper_chat_adapter_setting)

      assert_nil setting.service_account
    end

    should "return nil when the configured user is locked" do
      user = User.find(2)
      user.lock!
      setting = create(:ai_helper_chat_adapter_setting, redmine_user_id: user.id)

      assert_nil setting.service_account
    end
  end

  context "masked tokens" do
    should "mask all but the first four characters" do
      setting = AiHelperChatAdapterSetting.new(app_token: "xapp-123456", bot_token: "xoxb-abcdef")

      assert_equal "xapp#{'*' * 7}", setting.masked_app_token
      assert_equal "xoxb#{'*' * 7}", setting.masked_bot_token
    end

    should "return the token unchanged when blank or short" do
      setting = AiHelperChatAdapterSetting.new(app_token: nil, bot_token: "abc")

      assert_nil setting.masked_app_token
      assert_equal "abc", setting.masked_bot_token
    end
  end
end
