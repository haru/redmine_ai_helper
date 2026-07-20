# frozen_string_literal: true

require "redmine_ai_helper/logger"

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
        user = adapter_settings(message).service_account
        return reply(message, guidance(:service_account_not_configured, nil)) unless user

        project = resolve_project(message)
        unless project
          key = message.dm? ? :dm_not_configured : :channel_not_bound
          return reply(message, guidance(key, user))
        end
        return reply(message, guidance(:module_disabled, user)) unless project.module_enabled?(:ai_helper)

        answer = process_question(message, user, project)
        reply(message, answer.content)
      rescue => e
        ai_helper_logger.error "chat channel processing failed: #{e.full_message}"
        begin
          reply(message, guidance(:processing_failed, user))
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

      # Resolves the target project from the channel binding, or from the
      # adapter's DM default project for direct messages.
      # @return [Project, nil]
      def resolve_project(message)
        if message.dm?
          adapter_settings(message).dm_default_project
        else
          AiHelperChannelBinding.for_channel(message.channel_type, message.channel_id).first&.project
        end
      end

      # Appends the question to the thread's conversation and runs the LLM
      # under the service account's permissions.
      # @return [AiHelperMessage] The assistant's answer
      def process_question(message, user, project)
        conversation = AiHelperChannelConversation.find_or_create_conversation(
          channel_type: message.channel_type, thread_key: message.thread_key, user: user
        )
        if conversation.messages.empty?
          conversation.title = message.text.truncate(TITLE_MAX_LENGTH)
        end
        conversation.messages << AiHelperMessage.new(role: "user", content: message.text)
        conversation.save!

        begin
          User.current = user
          answer = RedmineAiHelper::Llm.new.chat(conversation, NOOP_PROC, { project: project })
        ensure
          User.current = User.anonymous
        end

        conversation.messages << answer
        conversation.save!
        answer
      end

      # Posts a reply into the thread the message came from.
      def reply(message, text)
        @adapter.send_message(channel_id: message.channel_id, thread_key: message.thread_key, text: text)
      end

      # Localized guidance text, preferring the service account's language.
      def guidance(key, user)
        locale = user&.language.presence || Setting.default_language
        I18n.t("ai_helper.chat_channel.errors.#{key}", locale: locale)
      end
    end
  end
end
