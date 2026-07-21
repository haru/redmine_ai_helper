# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelMessageHandlerTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  fixtures :projects, :users, :enabled_modules

  # In-memory adapter driving the handler without any external service.
  class RecordingAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :sent_messages

    class << self
      def channel_type
        "handler_chat"
      end
    end

    def initialize
      super
      @sent_messages = []
    end

    def start; end

    def stop; end

    def send_message(channel_id:, thread_key:, text:)
      @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
    end
  end

  setup do
    @adapter = RecordingAdapter.new
    @handler = @adapter.handler
    @project = Project.find(1)
    @project.enable_module!("ai_helper")
    @service_account = User.find(2)
    @setting = create(:ai_helper_chat_adapter_setting,
                      channel_type: "handler_chat", redmine_user_id: @service_account.id)
    create(:ai_helper_channel_binding, channel_type: "handler_chat", channel_id: "CH1", project: @project)
  end

  def incoming(text: "What are the open issues?", channel_id: "CH1", thread_key: "CH1:1.000001", dm: false)
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "handler_chat", channel_id: channel_id, thread_key: thread_key,
      text: text, dm: dm
    )
  end

  def error_text(key, user: @service_account)
    I18n.t("ai_helper.chat_channel.errors.#{key}",
           locale: user&.language.presence || Setting.default_language)
  end

  context "handle" do
    should "reply with guidance when no service account is configured" do
      @setting.update_column(:redmine_user_id, nil)

      @handler.handle(incoming)

      assert_equal 1, @adapter.sent_messages.size
      assert_equal error_text(:service_account_not_configured, user: nil),
                   @adapter.sent_messages.first[:text]
      assert_equal 0, AiHelperConversation.count
    end

    should "reply that the execution account is unavailable when it is locked" do
      @setting.update!(enabled: true)
      @service_account.lock!

      @handler.handle(incoming)

      assert_equal error_text(:service_account_unavailable, user: nil),
                   @adapter.sent_messages.first[:text]
      assert_equal 0, AiHelperConversation.count
    end

    should "reply that the execution account is unavailable when it was deleted" do
      # Deleting a Redmine user nullifies redmine_user_id via the FK's
      # on_delete: :nullify. Because FR-1 forbids saving an enabled adapter
      # without an account, an enabled row with a blank account can only mean
      # the previously configured account was removed.
      @setting.update!(enabled: true)
      @setting.update_column(:redmine_user_id, nil)

      @handler.handle(incoming)

      assert_equal error_text(:service_account_unavailable, user: nil),
                   @adapter.sent_messages.first[:text]
      assert_equal 0, AiHelperConversation.count
    end

    should "reply with guidance when the channel is not bound" do
      message = incoming(channel_id: "UNBOUND")
      @handler.handle(message)

      assert_equal error_text(:channel_not_bound), @adapter.sent_messages.first[:text]
    end

    should "reply with guidance for a DM without a default project" do
      message = incoming(dm: true, channel_id: "D123", thread_key: "D123:1.000001")
      @handler.handle(message)

      assert_equal error_text(:dm_not_configured), @adapter.sent_messages.first[:text]
    end

    should "use the DM default project for direct messages" do
      @setting.update!(dm_default_project_id: @project.id)
      RedmineAiHelper::Llm.any_instance.expects(:chat).with do |_conversation, _proc, option|
        option[:project] == @project
      end.returns(assistant_message("dm answer"))

      @handler.handle(incoming(dm: true, channel_id: "D123", thread_key: "D123:1.000001"))

      assert_equal "dm answer", @adapter.sent_messages.first[:text]
    end

    should "reply with guidance when the ai_helper module is disabled" do
      @project.disable_module!("ai_helper")
      message = incoming
      @handler.handle(message)

      assert_equal error_text(:module_disabled), @adapter.sent_messages.first[:text]
    end

    should "run the LLM as the service account and post the answer to the thread" do
      observed_user = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, proc, option|
        observed_user = User.current
        conversation.messages.last.content == "What are the open issues?" &&
          proc.respond_to?(:call) && option[:project] == Project.find(1)
      end.returns(assistant_message("Here are the issues"))

      message = incoming
      @handler.handle(message)

      assert_equal @service_account, observed_user
      assert_equal 1, @adapter.sent_messages.size
      sent = @adapter.sent_messages.first
      assert_equal "CH1", sent[:channel_id]
      assert_equal "CH1:1.000001", sent[:thread_key]
      assert_equal "Here are the issues", sent[:text]

      conversation = AiHelperConversation.first
      assert_equal @service_account, conversation.user
      assert_equal %w[user assistant], conversation.messages.order(:id).pluck(:role)
    end

    should "restore User.current to anonymous after handling" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("ok"))

      @handler.handle(incoming)

      assert_equal User.anonymous, User.current
    end

    should "set I18n.locale to the service account's language during processing" do
      @service_account.update!(language: "ja")

      observed_locale = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |_conversation, _proc, _option|
        observed_locale = I18n.locale
        true
      end.returns(assistant_message("ok"))

      @handler.handle(incoming)

      assert_equal :ja, observed_locale
    end

    should "restore the caller's I18n.locale after handling" do
      @service_account.update!(language: "ja")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("ok"))

      I18n.with_locale(:fr) do
        @handler.handle(incoming)

        assert_equal :fr, I18n.locale
      end
    end

    should "use Setting.default_language when service account language is blank" do
      @service_account.update!(language: "")
      observed_locale = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |_conversation, _proc, _option|
        observed_locale = I18n.locale
        true
      end.returns(assistant_message("ok"))

      @handler.handle(incoming)

      assert_equal Setting.default_language.to_sym, observed_locale
    end

    should "restore the caller's I18n.locale even when processing raises" do
      @service_account.update!(language: "ja")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).raises(RuntimeError, "boom")

      I18n.with_locale(:fr) do
        @handler.handle(incoming)

        assert_equal :fr, I18n.locale
      end
    end

    should "reply with an error notice and log when processing raises" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).raises(RuntimeError, "boom")

      @handler.handle(incoming)

      assert_equal error_text(:processing_failed), @adapter.sent_messages.first[:text]
      assert_equal User.anonymous, User.current
    end

    should "not raise when posting the error notice itself fails" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).raises(RuntimeError, "boom")
      @adapter.expects(:send_message).raises(RuntimeError, "slack is down")

      assert_nothing_raised { @handler.handle(incoming) }
      assert_equal User.anonymous, User.current
    end
  end

  context "thread continuation" do
    should "append follow-up questions to the existing conversation with full history" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message("first answer"), assistant_message("second answer")
      )
      @handler.handle(incoming(text: "first question", thread_key: "CH1:9.000001"))

      observed_history = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, _proc, _option|
        observed_history = conversation.messages.order(:id).pluck(:role, :content)
        true
      end.returns(assistant_message("second answer"))
      @handler.handle(incoming(text: "second question", thread_key: "CH1:9.000001"))

      assert_equal 1, AiHelperConversation.count
      assert_equal [
        [ "user", "first question" ],
        [ "assistant", "first answer" ],
        [ "user", "second question" ]
      ], observed_history
    end

    should "process every question as the service account" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("answer"))
      @handler.handle(incoming(text: "starter question", thread_key: "CH1:9.000002"))

      observed_user = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |_conversation, _proc, _option|
        observed_user = User.current
        true
      end.returns(assistant_message("follow-up answer"))
      @handler.handle(incoming(text: "follow-up", thread_key: "CH1:9.000002"))

      assert_equal @service_account, observed_user
      assert_equal @service_account, AiHelperConversation.first.user
    end

    should "start a new conversation for a different thread" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("answer"))

      @handler.handle(incoming(thread_key: "CH1:9.000003"))
      @handler.handle(incoming(thread_key: "CH1:9.000004"))

      assert_equal 2, AiHelperConversation.count
    end

    should "set the conversation title from the head of the first question" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("answer"))
      long_question = "Q" * 80

      @handler.handle(incoming(text: long_question, thread_key: "CH1:9.000005"))

      title = AiHelperConversation.first.title
      assert_equal long_question.truncate(50), title
      assert_operator title.length, :<=, 50
    end
  end

  private

  def assistant_message(content)
    AiHelperMessage.new(role: "assistant", content: content)
  end
end
