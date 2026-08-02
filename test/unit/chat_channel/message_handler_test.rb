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

  # Adapter that supports history retrieval, used for the context import tests.
  class HistoryRecordingAdapter < RecordingAdapter
    attr_reader :calls
    attr_accessor :thread_history, :channel_history

    class << self
      def channel_type
        "handler_history_chat"
      end
    end

    def initialize
      super
      @calls = []
      @thread_history = []
      @channel_history = []
    end

    def supports_history?
      true
    end

    def fetch_thread_history(channel_id:, thread_key:, after: nil)
      @calls << { source: :thread, channel_id: channel_id, thread_key: thread_key, after: after }
      @thread_history
    end

    def fetch_channel_history(channel_id:, before:, since:, limit:)
      @calls << { source: :channel, channel_id: channel_id, before: before, since: since, limit: limit }
      @channel_history
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

  def history_incoming(text: "what about this?", channel_id: "CH2", thread_key: "CH2:1.000001",
                       message_ts: "1.000900", in_thread: true, dm: false)
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "handler_history_chat", channel_id: channel_id, thread_key: thread_key,
      message_ts: message_ts, text: text, dm: dm, in_thread: in_thread
    )
  end

  def history_message(speaker, text)
    RedmineAiHelper::ChatChannel::HistoryMessage.new(speaker: speaker, text: text)
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
      @setting.update!(enabled: true, default_project_id: @project.id)
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
      @setting.update!(enabled: true, default_project_id: @project.id)
      @setting.update_column(:redmine_user_id, nil)

      @handler.handle(incoming)

      assert_equal error_text(:service_account_unavailable, user: nil),
                   @adapter.sent_messages.first[:text]
      assert_equal 0, AiHelperConversation.count
    end

    should "fall back to the default project for an unbound channel (B1)" do
      @setting.update!(default_project_id: @project.id)
      RedmineAiHelper::Llm.any_instance.expects(:chat).with do |_conversation, _proc, option|
        option[:project] == @project
      end.returns(assistant_message("default answer"))

      @handler.handle(incoming(channel_id: "UNBOUND", thread_key: "UNBOUND:1.000001"))

      assert_equal "default answer", @adapter.sent_messages.first[:text]
    end

    should "prefer the channel binding over the default project for a bound channel (B2)" do
      other_project = Project.find(2)
      other_project.enable_module!("ai_helper")
      @setting.update!(default_project_id: other_project.id)
      RedmineAiHelper::Llm.any_instance.expects(:chat).with do |_conversation, _proc, option|
        option[:project] == @project
      end.returns(assistant_message("bound answer"))

      @handler.handle(incoming(channel_id: "CH1", thread_key: "CH1:2.000001"))

      assert_equal "bound answer", @adapter.sent_messages.first[:text]
    end

    should "use the default project for direct messages (B3)" do
      @setting.update!(default_project_id: @project.id)
      RedmineAiHelper::Llm.any_instance.expects(:chat).with do |_conversation, _proc, option|
        option[:project] == @project
      end.returns(assistant_message("dm answer"))

      @handler.handle(incoming(dm: true, channel_id: "D123", thread_key: "D123:1.000001"))

      assert_equal "dm answer", @adapter.sent_messages.first[:text]
    end

    should "reply with guidance for an unbound channel when no default project exists (B5)" do
      message = incoming(channel_id: "UNBOUND", thread_key: "UNBOUND:1.000001")
      @handler.handle(message)

      assert_equal error_text(:default_project_not_configured), @adapter.sent_messages.first[:text]
    end

    should "reply with guidance for a DM when no default project exists (B5)" do
      message = incoming(dm: true, channel_id: "D123", thread_key: "D123:1.000001")
      @handler.handle(message)

      assert_equal error_text(:default_project_not_configured), @adapter.sent_messages.first[:text]
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

    should "post the error notice without going through IssueLinkFormatter (S3)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).raises(RuntimeError, "boom")
      RedmineAiHelper::ChatChannel::IssueLinkFormatter.any_instance.expects(:format).never

      @handler.handle(incoming)

      assert_equal error_text(:processing_failed), @adapter.sent_messages.first[:text]
    end

    should "still deliver the error notice when the answer's own link formatting failed" do
      Setting.stubs(:host_name).returns("")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("see #1549"))

      @handler.handle(incoming)

      assert_equal error_text(:processing_failed), @adapter.sent_messages.first[:text]
    end
  end

  context "reply markup removal" do
    should "strip the AIHELPER_OPTIONS markup from the posted answer (T-1)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Here are the issues.\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      assert_equal "Here are the issues.", @adapter.sent_messages.first[:text]
    end

    should "leave the posted answer unchanged when it has no markup (T-2)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("Here are the issues."))

      @handler.handle(incoming)

      assert_equal "Here are the issues.", @adapter.sent_messages.first[:text]
    end

    should "not leave a trailing blank line after stripping the markup (T-3)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Here are the issues.\n\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      assert_equal "Here are the issues.", @adapter.sent_messages.first[:text]
    end

    should "post the empty_answer guidance when the answer is only markup (T-4)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      assert_equal error_text(:empty_answer), @adapter.sent_messages.first[:text]
    end

    should "strip the markup and post the body without raising when the embedded JSON is malformed (T-5)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Here are the issues.\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a"-->))
      )

      assert_nothing_raised { @handler.handle(incoming) }

      assert_equal "Here are the issues.", @adapter.sent_messages.first[:text]
    end

    should "strip every markup block when the answer contains more than one (T-6)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Part one.<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->Part two.<!--AIHELPER_OPTIONS:{"choices":[{"label":"b","value":"b"}]}-->))
      )

      @handler.handle(incoming)

      text = @adapter.sent_messages.first[:text]
      assert_no_match(/AIHELPER_OPTIONS/, text)
      assert_match(/Part one\./, text)
      assert_match(/Part two\./, text)
    end

    should "strip a markup block in the middle of the answer and keep the surrounding text (T-7)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Before.<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->After.))
      )

      @handler.handle(incoming)

      text = @adapter.sent_messages.first[:text]
      assert_no_match(/AIHELPER_OPTIONS/, text)
      assert_match(/Before\./, text)
      assert_match(/After\./, text)
    end

    should "strip the markup even though the adapter implements no removal logic of its own (T-12)" do
      # RecordingAdapter#send_message (above) stores whatever text it is given
      # verbatim, so a clean result here proves the guarantee is structural to
      # MessageHandler and not something each adapter must implement (FR-003).
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Here are the issues.\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      assert_equal "Here are the issues.", @adapter.sent_messages.first[:text]
    end

    should "not save the markup in the conversation history (T-8)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(Here are the issues.\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      answer = AiHelperConversation.first.messages.order(:id).last
      assert_equal "Here are the issues.", answer.content
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

    should "not hand the markup from a previous answer back to the LLM (T-9)" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(first answer\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )
      @handler.handle(incoming(text: "first question", thread_key: "CH1:9.000010"))

      observed_history = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, _proc, _option|
        observed_history = conversation.messages.order(:id).pluck(:role, :content)
        true
      end.returns(assistant_message("second answer"))
      @handler.handle(incoming(text: "second question", thread_key: "CH1:9.000010"))

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

  context "issue link rendering" do
    setup do
      Setting.stubs(:protocol).returns("https")
      Setting.stubs(:host_name).returns("r.example.com")
    end

    should "V-12: post text with PLAIN link format for an adapter that does not declare one" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("See #1549 for details."))

      @handler.handle(incoming)

      assert_match(/#1549 \(https:\/\/r\.example\.com\/issues\/1549\)/, @adapter.sent_messages.first[:text])
    end

    should "V-13: strip UI control markup before converting issue links" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(See #1549.\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @handler.handle(incoming)

      text = @adapter.sent_messages.first[:text]
      assert_no_match(/AIHELPER_OPTIONS/, text, "markup must be stripped first")
      assert_match(/#1549 \(https:\/\/r\.example\.com\/issues\/1549\)/, text, "links rendered after stripping")
    end

    should "V-16: not change guidance text that has no issue references" do
      @setting.update_column(:redmine_user_id, nil)

      @handler.handle(incoming)

      text = @adapter.sent_messages.first[:text]
      assert_equal error_text(:service_account_not_configured, user: nil), text
    end

    should "V-17: render links for DM, channel and thread routes" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("See #1549."))
      @setting.update!(default_project_id: @project.id)

      @handler.handle(incoming(dm: true, channel_id: "D1", thread_key: "D1:1.000001"))
      dm_text = @adapter.sent_messages.first[:text]
      assert_match(/#1549 \(https:\/\/r\.example\.com\/issues\/1549\)/, dm_text)

      @handler.handle(incoming(channel_id: "CH1", thread_key: "CH1:2.000001"))
      channel_text = @adapter.sent_messages.last[:text]
      assert_match(/#1549 \(https:\/\/r\.example\.com\/issues\/1549\)/, channel_text)

      @handler.handle(incoming(text: "another question", thread_key: "CH1:9.000001"))
      thread_text = @adapter.sent_messages.last[:text]
      assert_match(/#1549 \(https:\/\/r\.example\.com\/issues\/1549\)/, thread_text)
    end

    should "V-14: save the original #1549 without link syntax in conversation history" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("See #1549."))

      @handler.handle(incoming)

      answer = AiHelperConversation.first.messages.order(:id).last
      assert_equal "See #1549.", answer.content
      assert_no_match(/r\.example\.com/, answer.content, "link syntax must not leak into saved content")
    end

    should "V-15: not include link syntax in the context handed to the LLM on a follow-up" do
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("See #1549."))

      @handler.handle(incoming(text: "first question", thread_key: "CH1:9.000010"))

      observed_history = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, _proc, _option|
        observed_history = conversation.messages.order(:id).pluck(:role, :content)
        true
      end.returns(assistant_message("second answer"))
      @handler.handle(incoming(text: "follow-up", thread_key: "CH1:9.000010"))

      observed_history.each do |_role, content|
        assert_no_match(/r\.example\.com/, content, "link syntax must not reach the LLM as context")
      end
    end
  end

  context "context import" do
    setup do
      @history_adapter = HistoryRecordingAdapter.new
      @history_handler = @history_adapter.handler
      @history_setting = create(:ai_helper_chat_adapter_setting,
                                channel_type: "handler_history_chat", redmine_user_id: @service_account.id)
      create(:ai_helper_channel_binding,
             channel_type: "handler_history_chat", channel_id: "CH2", project: @project)
    end

    should "import the context before the question is appended to the conversation" do
      @history_adapter.thread_history = [ history_message("Yamada", "it crashes on save") ]
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming(text: "why does it crash?"))

      conversation = AiHelperConversation.first
      assert_equal [
        [ "context", "Yamada: it crashes on save" ],
        [ "user", "why does it crash?" ],
        [ "assistant", "the answer" ]
      ], conversation.messages.order(:id).pluck(:role, :content)
    end

    should "decide the conversation title before the context is imported" do
      @history_adapter.thread_history = [ history_message("Yamada", "it crashes on save") ]
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming(text: "why does it crash?"))

      assert_equal "why does it crash?", AiHelperConversation.first.title
    end

    should "log the failure and prepend the notice to the answer when the import fails" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))
      logger = mock("logger")
      logger.stubs(:info)
      logger.stubs(:warn)
      logger.stubs(:debug)
      logger.expects(:error).with(regexp_matches(/history scope missing/))
      @history_handler.stubs(:ai_helper_logger).returns(logger)

      @history_handler.handle(history_incoming)

      notice = error_text(:history_unavailable)
      assert @history_adapter.sent_messages.first[:text].start_with?(notice),
             "the posted answer must start with the notice"
      answer = AiHelperConversation.first.messages.order(:id).last
      assert answer.content.start_with?(notice), "the stored answer must contain the notice as well"
      assert_match(/the answer/, answer.content)
    end

    should "keep the history_unavailable notice while stripping trailing markup (T-11)" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(the answer\n<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @history_handler.handle(history_incoming)

      notice = error_text(:history_unavailable)
      posted = @history_adapter.sent_messages.first[:text]
      assert posted.start_with?(notice), "the posted answer must start with the notice"
      assert_no_match(/AIHELPER_OPTIONS/, posted)

      answer = AiHelperConversation.first.messages.order(:id).last
      assert answer.content.start_with?(notice), "the stored answer must contain the notice as well"
      assert_no_match(/AIHELPER_OPTIONS/, answer.content)
    end

    should "use the empty_answer guidance, not overridden by the history notice, when the body is markup-only and the import fails (T-13)" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        assistant_message(%(<!--AIHELPER_OPTIONS:{"choices":[{"label":"a","value":"a"}]}-->))
      )

      @history_handler.handle(history_incoming)

      history_notice = error_text(:history_unavailable)
      empty_notice = error_text(:empty_answer)
      posted = @history_adapter.sent_messages.first[:text]
      assert_equal "#{history_notice}\n\n#{empty_notice}", posted

      answer = AiHelperConversation.first.messages.order(:id).last
      assert_equal "#{history_notice}\n\n#{empty_notice}", answer.content
    end

    should "still answer when the import fails" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming)

      assert_equal 1, @history_adapter.sent_messages.size
      assert_match(/the answer/, @history_adapter.sent_messages.first[:text])
    end

    should "not keep the import cursor when the import failed" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming)

      assert_nil AiHelperConversation.first.channel_conversation.last_imported_message_key
    end

    should "leave only user and assistant messages in the conversation when the import fails" do
      @history_adapter.stubs(:fetch_thread_history).raises(RuntimeError, "history scope missing")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming)

      roles = AiHelperConversation.first.messages.order(:id).pluck(:role)
      assert_equal %w[user assistant], roles, "no orphaned context messages must remain"
    end

    should "not store the rolled back context messages when the import transaction fails" do
      @history_adapter.thread_history = [ history_message("Yamada", "it crashes on save") ]
      AiHelperChannelConversation.any_instance.stubs(:update!).raises(RuntimeError, "cursor update failed")
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming(text: "why does it crash?"))

      roles = AiHelperConversation.first.messages.order(:id).pluck(:role)
      assert_equal %w[user assistant], roles, "the rolled back context messages must not be saved again"
    end

    should "not hand the rolled back context messages to the LLM when the import transaction fails" do
      @history_adapter.thread_history = [ history_message("Yamada", "it crashes on save") ]
      AiHelperChannelConversation.any_instance.stubs(:update!).raises(RuntimeError, "cursor update failed")
      handover = nil
      RedmineAiHelper::Llm.any_instance.stubs(:chat).with do |conversation, _proc, _option|
        handover = conversation.messages_for_openai
        true
      end.returns(assistant_message("the answer"))

      @history_handler.handle(history_incoming(text: "why does it crash?"))

      assert_equal [ { role: "user", content: "why does it crash?" } ], handover,
                   "the notice says the history is unavailable, so no context may reach the LLM"
    end

    should "not fetch any history when no execution account is configured (FR-013)" do
      @history_setting.update_column(:redmine_user_id, nil)
      @history_adapter.expects(:fetch_thread_history).never
      @history_adapter.expects(:fetch_channel_history).never

      @history_handler.handle(history_incoming)

      assert_equal 0, AiHelperConversation.count
    end

    should "not fetch any history when the project cannot be resolved (FR-013)" do
      @history_adapter.expects(:fetch_thread_history).never
      @history_adapter.expects(:fetch_channel_history).never

      @history_handler.handle(history_incoming(channel_id: "UNBOUND", thread_key: "UNBOUND:1.000001"))

      assert_equal error_text(:default_project_not_configured), @history_adapter.sent_messages.first[:text]
    end

    should "not fetch any history when the ai_helper module is disabled (FR-013)" do
      @project.disable_module!("ai_helper")
      @history_adapter.expects(:fetch_thread_history).never
      @history_adapter.expects(:fetch_channel_history).never

      @history_handler.handle(history_incoming)

      assert_equal error_text(:module_disabled), @history_adapter.sent_messages.first[:text]
    end
  end

  private

  def assistant_message(content)
    AiHelperMessage.new(role: "assistant", content: content)
  end
end
