# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/history_message"

module RedmineAiHelper
  module ChatChannel
    # Imports the messages surrounding a mention into the conversation bound to
    # the thread. The imported messages are stored as regular conversation
    # messages with role "context", so they reach the LLM through the existing
    # conversation handover and stay visible in the Redmine chat history.
    class ContextImporter
      include RedmineAiHelper::Logger

      # Age of the oldest top-level message imported in channel mode.
      CONTEXT_LOOKBACK_HOURS = 48

      # Maximum number of top-level messages imported in channel mode.
      CONTEXT_MESSAGE_LIMIT = 20

      # @param adapter [BaseAdapter] the adapter retrieving the history
      def initialize(adapter)
        @adapter = adapter
      end

      # Imports the messages that have not been imported yet. Must be called
      # before the question itself is appended to the conversation, because the
      # conversation being empty is what distinguishes a new conversation
      # started outside a thread from a continuing one.
      # @param conversation [AiHelperConversation] the thread's conversation;
      #   must have an associated channel_conversation
      # @param message [IncomingMessage] the mention being processed; +message_ts+
      #   must not be nil (it becomes the import cursor)
      # @return [Integer] the number of imported messages
      # @raise [StandardError] when the adapter fails to retrieve the history
      def import(conversation:, message:)
        return 0 unless @adapter.supports_history?

        source = import_source(conversation: conversation, message: message)
        return 0 unless source

        history = fetch_history(source: source, conversation: conversation, message: message)
        store(conversation: conversation, message: message, history: history)
        ai_helper_logger.info "chat channel: imported #{history.size} context messages " \
                              "from #{source} (conversation #{conversation.id})"
        history.size
      end

      private

      # Which retrieval mode applies to this mention, or nil when nothing is
      # imported. A mention outside a thread that continues an existing
      # conversation imports nothing: following the channel along is out of
      # scope for this feature.
      # @return [Symbol, nil] :thread, :channel or nil
      def import_source(conversation:, message:)
        return :thread if message.in_thread?
        return :channel if conversation.messages.empty?

        nil
      end

      # Retrieves the not-yet-imported messages for the resolved mode.
      # @return [Array<HistoryMessage>] ascending (oldest first)
      def fetch_history(source:, conversation:, message:)
        if source == :thread
          @adapter.fetch_thread_history(
            channel_id: message.channel_id, thread_key: message.thread_key,
            after: conversation.channel_conversation.last_imported_message_key
          )
        else
          @adapter.fetch_channel_history(
            channel_id: message.channel_id, before: message.message_ts,
            since: CONTEXT_LOOKBACK_HOURS.hours.ago, limit: CONTEXT_MESSAGE_LIMIT
          )
        end
      end

      # Appends the retrieved messages to the conversation and advances the
      # import cursor. Both happen in one transaction so a failure can never
      # leave the cursor ahead of what was actually stored. In thread mode the
      # cursor prevents the same range from being scanned again; in channel
      # mode it is advanced for consistency but channel mode only fires once
      # (when the conversation is empty).
      # @return [void]
      def store(conversation:, message:, history:)
        AiHelperConversation.transaction do
          history.each do |imported|
            conversation.messages << AiHelperMessage.new(
              role: AiHelperMessage::CONTEXT_ROLE, content: "#{imported.speaker}: #{imported.text}"
            )
          end
          conversation.save!
          conversation.channel_conversation.update!(last_imported_message_key: message.message_ts)
        end
      end
    end
  end
end
