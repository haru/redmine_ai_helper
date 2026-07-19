# frozen_string_literal: true

module RedmineAiHelper
  module ChatChannel
    # Value object holding a chat tool event normalized by an adapter.
    # Adapters guarantee that +text+ has mention markup removed and that
    # bot-originated events are never wrapped in an IncomingMessage.
    # The speaker's identity is deliberately not carried: all questions are
    # processed as the configured service account (FR-004).
    class IncomingMessage
      attr_reader :channel_type, :channel_id, :thread_key, :message_ts, :text

      # @param channel_type [String] Adapter identifier (e.g. "slack")
      # @param channel_id [String] Channel identifier (DM channel id for DMs)
      # @param thread_key [String] Tool-specific thread identifier
      # @param text [String] Question body with mention markup removed
      # @param message_ts [String, nil] Identifier of this individual message
      #   (Slack +ts+), distinct from the thread key. Used to attach the
      #   processing notice to the message that was actually sent, so replies
      #   within a thread each get their own notice instead of colliding on
      #   the thread's root message.
      # @param dm [Boolean] Whether the message is a direct message
      def initialize(channel_type:, channel_id:, thread_key:, text:, message_ts: nil, dm: false)
        @channel_type = channel_type
        @channel_id = channel_id
        @thread_key = thread_key
        @message_ts = message_ts
        @text = text
        @dm = dm
      end

      # Whether the message is a direct message.
      # @return [Boolean]
      def dm?
        @dm
      end
    end
  end
end
