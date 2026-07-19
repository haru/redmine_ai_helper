# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelBaseAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # In-memory adapter used to verify that subclassing BaseAdapter alone is
  # enough to plug a new chat tool into the abstraction layer (SC-006).
  class FakeAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :sent_messages, :processing_notified
    attr_accessor :user_email

    class << self
      def channel_type
        "fake_chat"
      end

      def required_setting_fields
        [ :bot_token ]
      end
    end

    def initialize
      super
      @sent_messages = []
      @processing_notified = []
    end

    def start
      # No external connection for the in-memory adapter.
    end

    def stop
      # Nothing to close.
    end

    def send_message(channel_id:, thread_key:, text:)
      @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
    end

    def resolve_user_email(external_user_id:)
      @user_email || "fake-#{external_user_id}@example.com"
    end

    def notify_processing(message:)
      @processing_notified << message
    end
  end

  context "automatic registration" do
    should "register subclasses by channel_type" do
      assert_equal FakeAdapter, RedmineAiHelper::ChatChannel::BaseAdapter.adapters["fake_chat"]
    end
  end

  context "settings" do
    should "return the AiHelperChatAdapterSetting for the adapter's channel_type" do
      setting = create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat")

      assert_equal setting, FakeAdapter.new.settings
    end
  end

  context "enabled?" do
    should "be false when no setting exists" do
      assert_not FakeAdapter.new.enabled?
    end

    should "be false when the setting is enabled but a required field is missing" do
      setting = create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", bot_token: nil)
      # Bypass validation to simulate a row saved before the adapter declared
      # the field as required.
      setting.update_column(:enabled, true)

      assert_not FakeAdapter.new.enabled?
    end

    should "be true when enabled and all required fields are present" do
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", enabled: true, bot_token: "xoxb-token")

      assert_predicate FakeAdapter.new, :enabled?
    end
  end

  context "handler" do
    should "provide a MessageHandler bound to the adapter" do
      adapter = FakeAdapter.new

      assert_kind_of RedmineAiHelper::ChatChannel::MessageHandler, adapter.handler
    end
  end

  # SC-006: a brand-new tool integration must work end to end with nothing
  # but a BaseAdapter subclass — no changes to MessageHandler, the models or
  # the Slack adapter.
  context "end-to-end with a fictional adapter" do
    should "accept a question and return the answer through the shared core" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      adapter = FakeAdapter.new
      adapter.user_email = user.mail
      create(:ai_helper_channel_binding, channel_type: "fake_chat", channel_id: "FC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "fictional answer")
      )

      adapter.dispatch(RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "FC1", thread_key: "FC1:1.000001",
        text: "hello from a fictional tool", external_user_id: "U1", dm: false
      ))

      assert_equal 1, adapter.processing_notified.size
      assert_equal [ { channel_id: "FC1", thread_key: "FC1:1.000001", text: "fictional answer" } ],
                   adapter.sent_messages
      conversation = AiHelperConversation.first
      assert_equal user, conversation.user
      assert_equal "fake_chat", conversation.channel_conversation.channel_type
    end
  end

  context "IncomingMessage" do
    should "hold the normalized fields" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat",
        channel_id: "C123",
        thread_key: "C123:1700000000.000100",
        text: "hello",
        external_user_id: "U123",
        dm: true
      )

      assert_equal "fake_chat", message.channel_type
      assert_equal "C123", message.channel_id
      assert_equal "C123:1700000000.000100", message.thread_key
      assert_equal "hello", message.text
      assert_equal "U123", message.external_user_id
      assert message.dm
    end
  end
end
