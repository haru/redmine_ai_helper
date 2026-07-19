# frozen_string_literal: true

module RedmineAiHelper
  module ChatChannel
    # Value object holding a chat tool event normalized by an adapter.
    # Adapters guarantee that +text+ has mention markup removed and that
    # bot-originated events are never wrapped in an IncomingMessage.
    class IncomingMessage
      attr_reader :channel_type, :channel_id, :thread_key, :text, :external_user_id

      # @param channel_type [String] Adapter identifier (e.g. "slack")
      # @param channel_id [String] Channel identifier (DM channel id for DMs)
      # @param thread_key [String] Tool-specific thread identifier
      # @param text [String] Question body with mention markup removed
      # @param external_user_id [String] Tool-specific user identifier
      # @param dm [Boolean] Whether the message is a direct message
      def initialize(channel_type:, channel_id:, thread_key:, text:, external_user_id:, dm: false)
        @channel_type = channel_type
        @channel_id = channel_id
        @thread_key = thread_key
        @text = text
        @external_user_id = external_user_id
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
