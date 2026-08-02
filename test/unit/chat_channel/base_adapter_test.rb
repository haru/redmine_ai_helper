# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelBaseAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # In-memory adapter used to verify that subclassing BaseAdapter alone is
  # enough to plug a new chat tool into the abstraction layer (SC-006).
  class FakeAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :sent_messages

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
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", enabled: true, bot_token: "xoxb-token", redmine_user_id: 2, default_project_id: 1)

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
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "fake_chat", channel_id: "FC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "fictional answer")
      )

      adapter.dispatch(RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "FC1", thread_key: "FC1:1.000001",
        text: "hello from a fictional tool", dm: false
      ))

      assert_equal [ { channel_id: "FC1", thread_key: "FC1:1.000001", text: "fictional answer" } ],
                   adapter.sent_messages
      conversation = AiHelperConversation.first
      assert_equal user, conversation.user
      assert_equal "fake_chat", conversation.channel_conversation.channel_type
    end
  end

  context "history support" do
    should "not support history by default" do
      assert_not_predicate FakeAdapter.new, :supports_history?
    end

    should "raise NotImplementedError from fetch_thread_history" do
      error = assert_raises(NotImplementedError) do
        FakeAdapter.new.fetch_thread_history(channel_id: "FC1", thread_key: "FC1:1.000001")
      end

      assert_match(/fetch_thread_history/, error.message)
    end

    should "raise NotImplementedError from fetch_channel_history" do
      error = assert_raises(NotImplementedError) do
        FakeAdapter.new.fetch_channel_history(
          channel_id: "FC1", before: "1.000002", since: 48.hours.ago, limit: 20
        )
      end

      assert_match(/fetch_channel_history/, error.message)
    end
  end

  # SC-006: an adapter that does not implement history retrieval keeps working
  # through the unchanged core; the only difference is that no prior context is
  # available to the answer.
  context "end-to-end with an adapter that does not support history" do
    should "answer without fetching or storing any context" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      adapter = FakeAdapter.new
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "fake_chat", channel_id: "FC2", project: project)
      adapter.expects(:fetch_thread_history).never
      adapter.expects(:fetch_channel_history).never
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "answer without context")
      )

      adapter.dispatch(RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "FC2", thread_key: "FC2:1.000001",
        message_ts: "1.000001", text: "hello", dm: false
      ))

      assert_equal "answer without context", adapter.sent_messages.first[:text]
      conversation = AiHelperConversation.first
      assert_equal %w[user assistant], conversation.messages.order(:id).pluck(:role)
      assert_nil conversation.channel_conversation.last_imported_message_key
    end
  end

  context "IncomingMessage" do
    should "hold the normalized fields" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat",
        channel_id: "C123",
        thread_key: "C123:1700000000.000100",
        message_ts: "1700000000.000200",
        text: "hello",
        dm: true
      )

      assert_equal "fake_chat", message.channel_type
      assert_equal "C123", message.channel_id
      assert_equal "C123:1700000000.000100", message.thread_key
      assert_equal "1700000000.000200", message.message_ts
      assert_equal "hello", message.text
      assert message.dm?
    end

    should "not be in a thread unless the adapter says so" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "C123", thread_key: "C123:1.000100", text: "hello"
      )

      assert_not_predicate message, :in_thread?
    end

    should "carry the in_thread flag set by the adapter" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "C123", thread_key: "C123:1.000100",
        text: "hello", in_thread: true
      )

      assert_predicate message, :in_thread?
    end
  end

  context "issue link format" do
    should "V-18: return PLAIN format when the adapter does not declare one" do
      adapter = FakeAdapter.new

      assert_equal RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN,
                   adapter.issue_link_format
    end

    should "V-20: have render results that match the format's pattern for PLAIN" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end

    should "V-20: have render results that match the format's pattern for SLACK" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end

    should "V-20: have render results that match the format's pattern for DISCORD" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::DISCORD
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end
  end
end
