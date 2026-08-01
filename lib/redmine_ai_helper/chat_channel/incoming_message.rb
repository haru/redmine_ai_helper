# frozen_string_literal: true

module RedmineAiHelper
  module ChatChannel
    # Value object holding a chat tool event normalized by an adapter.
    # Adapters guarantee that +text+ has mention markup removed and that
    # bot-originated events are never wrapped in an IncomingMessage.
    # The speaker's identity is deliberately not carried: all questions are
    # processed as the configured service account (FR-004).
    class IncomingMessage
      # @return [String] Adapter identifier (e.g. "slack")
      attr_reader :channel_type
      # @return [String] Channel identifier (DM channel id for DMs)
      attr_reader :channel_id
      # @return [String] Tool-specific thread identifier
      attr_reader :thread_key
      # @return [String, nil] Identifier of this individual message (Slack
      #   +ts+, Discord snowflake). Used as the import cursor
      #   (ContextImporter#store), the channel-history boundary
      #   (ContextImporter#fetch_history), and to attach processing notices
      #   to the message that was actually sent.
      attr_reader :message_ts
      # @return [String] Question body with mention markup removed
      attr_reader :text

      # @param channel_type [String] Adapter identifier (e.g. "slack")
      # @param channel_id [String] Channel identifier (DM channel id for DMs)
      # @param thread_key [String] Tool-specific thread identifier
      # @param text [String] Question body with mention markup removed
      # @param message_ts [String, nil] Identifier of this individual message
      #   (Slack +ts+, Discord snowflake), distinct from the thread key. Used
      #   as the differential-import cursor, the channel-history +before+
      #   boundary, and to attach processing notices to the correct message so
      #   replies within a thread each get their own notice.
      # @param dm [Boolean] Whether the message is a direct message
      # @param in_thread [Boolean] Whether the message was posted inside an
      #   existing thread. Adapters that cannot tell (or that do not retrieve
      #   history at all) leave this at false, which keeps the import in
      #   channel mode or skips it entirely.
      def initialize(channel_type:, channel_id:, thread_key:, text:, message_ts: nil, dm: false, in_thread: false)
        @channel_type = channel_type
        @channel_id = channel_id
        @thread_key = thread_key
        @message_ts = message_ts
        @text = text
        @dm = dm
        @in_thread = in_thread
        freeze
      end

      # Whether the message is a direct message.
      # @return [Boolean]
      def dm?
        @dm
      end

      # Whether the message was posted inside an existing thread.
      # @return [Boolean]
      def in_thread?
        @in_thread
      end
    end
  end
end
