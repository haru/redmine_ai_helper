# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelMessageHandlerTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  fixtures :projects, :users, :enabled_modules

  # In-memory adapter driving the handler without any external service.
  class RecordingAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :sent_messages, :processing_notified, :resolve_calls
    attr_accessor :email_by_user_id

    class << self
      def channel_type
        "handler_chat"
      end
    end

    def initialize
      super
      @sent_messages = []
      @processing_notified = []
      @email_by_user_id = {}
      @resolve_calls = 0
    end

    def start; end

    def stop; end

    def send_message(channel_id:, thread_key:, text:)
      @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
    end

    def resolve_user_email(external_user_id:)
      @resolve_calls += 1
      @email_by_user_id[external_user_id]
    end

    def notify_processing(message:)
      @processing_notified << message
    end
  end

  setup do
    @adapter = RecordingAdapter.new
    @handler = @adapter.handler
    @project = Project.find(1)
    @project.enable_module!("ai_helper")
    @user = User.find(2)
    @adapter.email_by_user_id["EXT_JSMITH"] = @user.mail
    create(:ai_helper_channel_binding, channel_type: "handler_chat", channel_id: "CH1", project: @project)
  end

  def incoming(text: "What are the open issues?", channel_id: "CH1", thread_key: "CH1:1.000001", external_user_id: "EXT_JSMITH", dm: false)
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "handler_chat", channel_id: channel_id, thread_key: thread_key,
      text: text, external_user_id: external_user_id, dm: dm
    )
  end

  def error_text(key)
    I18n.t("ai_helper.chat_channel.errors.#{key}", locale: @user.language.presence || Setting.default_language)
  end

  context "handle" do
    should "notify processing before anything else" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("ok"))

      message = incoming
      @handler.handle(message)

      assert_equal [ message ], @adapter.processing_notified
    end

    should "reply with guidance when the user cannot be mapped" do
      message = incoming(external_user_id: "EXT_UNKNOWN")
      @handler.handle(message)

      assert_equal 1, @adapter.sent_messages.size
      assert_equal error_text(:user_not_mapped), @adapter.sent_messages.first[:text]
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
      create(:ai_helper_chat_adapter_setting, channel_type: "handler_chat", dm_default_project_id: @project.id)
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

    should "run the LLM as the resolved user and post the answer to the thread" do
      observed_user = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, proc, option|
        observed_user = User.current
        conversation.messages.last.content == "What are the open issues?" &&
          proc.respond_to?(:call) && option[:project] == Project.find(1)
      end.returns(assistant_message("Here are the issues"))

      message = incoming
      @handler.handle(message)

      assert_equal @user, observed_user
      assert_equal 1, @adapter.sent_messages.size
      sent = @adapter.sent_messages.first
      assert_equal "CH1", sent[:channel_id]
      assert_equal "CH1:1.000001", sent[:thread_key]
      assert_equal "Here are the issues", sent[:text]

      conversation = AiHelperConversation.first
      assert_equal @user, conversation.user
      assert_equal %w[user assistant], conversation.messages.order(:id).pluck(:role)
    end

    should "restore User.current to anonymous after handling" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("ok"))

      @handler.handle(incoming)

      assert_equal User.anonymous, User.current
    end

    should "reply with an error notice and log when processing raises" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).raises(RuntimeError, "boom")

      @handler.handle(incoming)

      assert_equal error_text(:processing_failed), @adapter.sent_messages.first[:text]
      assert_equal User.anonymous, User.current
    end
  end

  context "thread continuation" do
    setup do
      @other_user = User.find(3)
      @adapter.email_by_user_id["EXT_DLOPPER"] = @other_user.mail
    end

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

    should "process another user's follow-up under that user without changing the owner" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("answer"))
      @handler.handle(incoming(text: "starter question", thread_key: "CH1:9.000002"))

      observed_user = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |_conversation, _proc, _option|
        observed_user = User.current
        true
      end.returns(assistant_message("follow-up answer"))
      @handler.handle(incoming(text: "follow-up", thread_key: "CH1:9.000002", external_user_id: "EXT_DLOPPER"))

      assert_equal @other_user, observed_user
      assert_equal @user, AiHelperConversation.first.user
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

  context "user resolution cache" do
    include ActiveSupport::Testing::TimeHelpers

    setup do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("ok"))
    end

    should "resolve each external user only once within the TTL" do
      @handler.handle(incoming(thread_key: "CH1:1.000001"))
      @handler.handle(incoming(thread_key: "CH1:1.000002"))

      assert_equal 1, @adapter.resolve_calls
    end

    should "cache the unmapped result as well" do
      @handler.handle(incoming(external_user_id: "EXT_UNKNOWN", thread_key: "CH1:1.000001"))
      @handler.handle(incoming(external_user_id: "EXT_UNKNOWN", thread_key: "CH1:1.000002"))

      assert_equal 1, @adapter.resolve_calls
      assert_equal 2, @adapter.sent_messages.size
      assert(@adapter.sent_messages.all? { |sent| sent[:text] == error_text(:user_not_mapped) })
    end

    should "resolve again after the TTL has expired" do
      @handler.handle(incoming(thread_key: "CH1:1.000001"))
      travel 11.minutes do
        @handler.handle(incoming(thread_key: "CH1:1.000002"))
      end

      assert_equal 2, @adapter.resolve_calls
    end
  end

  private

  def assistant_message(content)
    AiHelperMessage.new(role: "assistant", content: content)
  end
end
