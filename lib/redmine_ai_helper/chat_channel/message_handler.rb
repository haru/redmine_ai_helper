# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/context_importer"
require "redmine_ai_helper/util/interactive_options_parser"

module RedmineAiHelper
  module ChatChannel
    # Tool-independent core processing for messages received from chat tool
    # adapters: resolves the service account and project, binds the thread to
    # a conversation and runs the LLM under the service account's permissions.
    # #handle may be called from the gateway's single worker thread or
    # directly via BaseAdapter#dispatch when no gateway is configured.
    class MessageHandler
      include RedmineAiHelper::Logger

      # Streaming callback used with Llm#chat; replies are posted in one piece.
      NOOP_PROC = proc { |_content| }

      # Maximum length of a conversation title taken from the first question.
      TITLE_MAX_LENGTH = 50

      # @param adapter [BaseAdapter] The adapter this handler replies through
      def initialize(adapter)
        @adapter = adapter
      end

      # Processes one normalized incoming message end to end. Errors are
      # reported back into the thread and logged; they are never swallowed
      # silently (FR-011).
      # @param message [IncomingMessage] The message to process
      # @return [void]
      def handle(message)
        user = nil
        setting = adapter_settings(message)
        user = setting.service_account
        unless user
          # FR-001 forbids saving an enabled adapter without an execution
          # account, so an enabled adapter that resolves no active account can
          # only mean the previously configured account was deleted (the FK
          # nullifies redmine_user_id) or locked. Distinguish that runtime
          # loss from an adapter that was simply never configured.
          key = setting.enabled ? :service_account_unavailable : :service_account_not_configured
          return reply(message, guidance(key, nil), nil)
        end

        project = resolve_project(message)
        unless project
          return reply(message, guidance(:default_project_not_configured, user), user)
        end
        return reply(message, guidance(:module_disabled, user), user) unless project.module_enabled?(:ai_helper)

        answer = process_question(message, user, project)
        reply(message, answer.content, user)
      rescue => e
        ai_helper_logger.error "chat channel processing failed: #{e.full_message}"
        begin
          reply(message, guidance(:processing_failed, user), user)
        rescue => reply_error
          ai_helper_logger.error "chat channel: failed to post error notice: #{reply_error.full_message}"
        end
      end

      private

      # The adapter settings row for the message's channel type.
      # @return [AiHelperChatAdapterSetting]
      def adapter_settings(message)
        AiHelperChatAdapterSetting.for_channel(message.channel_type)
      end

      # Resolves the target project for the message. Direct messages use the
      # adapter's default project. Regular channels prefer their channel
      # binding and fall back to the default project when no binding exists.
      # @return [Project, nil]
      def resolve_project(message)
        settings = adapter_settings(message)
        return settings.default_project if message.dm?

        binding = AiHelperChannelBinding.for_channel(message.channel_type, message.channel_id).first
        binding&.project || settings.default_project
      end

      # Imports the surrounding chat messages, appends the question to the
      # thread's conversation and runs the LLM under the service account's
      # permissions. The import runs before the question is appended, and
      # after the checks in #handle, so a question that is refused never
      # reaches the chat tool's history API (FR-013).
      # @return [AiHelperMessage] The assistant's answer
      def process_question(message, user, project)
        conversation = AiHelperChannelConversation.find_or_create_conversation(
          channel_type: message.channel_type, thread_key: message.thread_key, user: user
        )
        new_conversation = conversation.messages.empty?
        history_unavailable = import_context(conversation, message)

        conversation.title = message.text.truncate(TITLE_MAX_LENGTH) if new_conversation
        conversation.messages << AiHelperMessage.new(role: "user", content: message.text)
        conversation.save!

        original_locale = I18n.locale
        begin
          User.current = user
          I18n.locale = user.language.presence || Setting.default_language
          answer = RedmineAiHelper::Llm.new.chat(conversation, NOOP_PROC, { project: project })
        ensure
          User.current = User.anonymous
          I18n.locale = original_locale
        end

        # Strip UI control markup before persisting the assistant message so it
        # won't be replayed to the LLM as thread context later (FR-007).
        # Outbound replies are stripped again in #reply to guarantee every
        # adapter post is clean, including early guidance replies.
        answer.content = strip_ui_options(answer.content, user)
        answer.content = "#{guidance(:history_unavailable, user)}\n\n#{answer.content}" if history_unavailable
        conversation.messages << answer
        conversation.save!
        answer
      end

      # Imports the messages surrounding the mention. A retrieval failure is
      # logged and reported to the user (FR-008) instead of aborting the
      # answer; the notice is added to the answer by the caller. This is a
      # deliberate deviation from the general "never swallow errors" guideline:
      # the error is fully logged with backtrace and explicitly surfaced to
      # the user, so the fallback is not silent.
      # @return [Boolean] whether the import failed
      def import_context(conversation, message)
        ContextImporter.new(@adapter).import(conversation: conversation, message: message)
        false
      rescue => e
        ai_helper_logger.error "chat channel: could not import the conversation context: #{e.full_message}"
        true
      end

      # Posts a reply into the thread the message came from. The reply text
      # is the sole gateway to every chat tool adapter (FR-002), so stripping
      # the UI control markup here guarantees no adapter needs its own
      # removal logic (FR-003).
      # @param user [User, nil] the service account, for guidance localization;
      #   nil when called before the account is resolved (#handle's early guidance replies)
      def reply(message, text, user = nil)
        @adapter.send_message(channel_id: message.channel_id, thread_key: message.thread_key,
                               text: strip_ui_options(text, user))
      end

      # Removes the UI control markup from text bound for a chat tool adapter
      # or the conversation history, falling back to the empty_answer guidance
      # when nothing but markup remains (FR-008).
      # @return [String]
      def strip_ui_options(text, user)
        stripped = RedmineAiHelper::Util::InteractiveOptionsParser.strip(text)
        stripped.presence || guidance(:empty_answer, user)
      end

      # Localized guidance text, preferring the service account's language.
      def guidance(key, user)
        locale = user&.language.presence || Setting.default_language
        I18n.t("ai_helper.chat_channel.errors.#{key}", locale: locale)
      end
    end
  end
end
