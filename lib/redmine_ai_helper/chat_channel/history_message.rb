# frozen_string_literal: true

module RedmineAiHelper
  module ChatChannel
    # Value object holding one message retrieved from a chat tool's history.
    # Adapters return these in ascending (oldest first) order with the
    # tool-specific concerns already resolved: the speaker is a display name,
    # the text has mention markup removed, and messages that must not be
    # imported (own messages, mentions of the bot, system messages, empty
    # bodies) have already been filtered out.
    # No timestamp is carried: the retrieval window is applied inside the
    # adapter and the order within the conversation expresses the sequence.
    class HistoryMessage
      # @return [String] the speaker's display name in the chat tool
      attr_reader :speaker

      # @return [String] the message body
      attr_reader :text

      # @param speaker [String] the speaker's display name (human or bot)
      # @param text [String] the message body without mention markup
      def initialize(speaker:, text:)
        @speaker = speaker
        @text = text
        freeze
      end
    end
  end
end
