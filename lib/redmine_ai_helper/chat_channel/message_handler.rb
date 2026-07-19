# frozen_string_literal: true

require "redmine_ai_helper/logger"

module RedmineAiHelper
  module ChatChannel
    # Tool-independent core processing for messages received from chat tool
    # adapters: resolves the Redmine user and project, binds the thread to a
    # conversation and runs the LLM under the speaker's own permissions.
    # #handle is only ever called from the gateway's single worker thread, so
    # User.current is safe to set and restore within one call.
    class MessageHandler
      include RedmineAiHelper::Logger

      # Streaming callback used with Llm#chat; replies are posted in one piece.
      NOOP_PROC = proc { |_content| }

      # Maximum length of a conversation title taken from the first question.
      TITLE_MAX_LENGTH = 50

      # How long a resolved external user (or the "no match" result) stays
      # cached in memory (research.md R-005).
      USER_CACHE_TTL = 10.minutes

      # @param adapter [BaseAdapter] The adapter this handler replies through
      def initialize(adapter)
        @adapter = adapter
        @user_cache = {}
      end

      # Processes one normalized incoming message end to end. Errors are
      # reported back into the thread and logged; they are never swallowed
      # silently (FR-011).
      # @param message [IncomingMessage] The message to process
      # @return [void]
      def handle(message)
        @adapter.notify_processing(message: message)

        user = resolve_user(message)
        return reply(message, guidance(:user_not_mapped, nil)) unless user

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
        reply(message, guidance(:processing_failed, user))
      end

      private

      # Resolves the Redmine user for the message speaker by email address.
      # Results (including "no match") are cached in memory with a TTL so
      # repeated questions do not hit the external user API every time.
      # @return [User, nil]
      def resolve_user(message)
        cached = @user_cache[message.external_user_id]
        return cached[:user] if cached && cached[:expires_at] > Time.zone.now

        email = @adapter.resolve_user_email(external_user_id: message.external_user_id)
        user = email.blank? ? nil : User.active.having_mail(email).first
        @user_cache[message.external_user_id] = { user: user, expires_at: Time.zone.now + USER_CACHE_TTL }
        user
      end

      # Resolves the target project from the channel binding, or from the
      # adapter's DM default project for direct messages.
      # @return [Project, nil]
      def resolve_project(message)
        if message.dm?
          AiHelperChatAdapterSetting.for_channel(message.channel_type).dm_default_project
        else
          AiHelperChannelBinding.for_channel(message.channel_type, message.channel_id).first&.project
        end
      end

      # Appends the question to the thread's conversation and runs the LLM
      # under the speaker's own permissions.
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

      # Localized guidance text, preferring the resolved user's language.
      def guidance(key, user)
        locale = user&.language.presence || Setting.default_language
        I18n.t("ai_helper.chat_channel.errors.#{key}", locale: locale)
      end
    end
  end
end
