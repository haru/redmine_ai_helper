# frozen_string_literal: true

require "redmine_ai_helper/chat_channel/incoming_message"

module RedmineAiHelper
  module ChatChannel
    # An IncomingMessage built from a stored inbound event, carrying the id of
    # the +ai_helper_inbound_events+ row it came from.
    #
    # The id travels with the message through the gateway queue so that, while
    # the message is being answered, +InboundAdapter#reply_metadata_for+ can
    # resolve that exact event rather than infer it from the thread. It lives
    # in a subclass rather than in IncomingMessage itself because it is
    # meaningful only to inbound adapters: the tool-independent core, the
    # outbound adapters and the value object they all share stay unchanged
    # (contracts/inbound_adapter.md INV-I5).
    class InboundEventMessage < IncomingMessage
      # @return [Integer] id of the ai_helper_inbound_events row
      attr_reader :event_id

      # @param event_id [Integer] id of the ai_helper_inbound_events row
      # @param attrs [Hash] the IncomingMessage attributes
      def initialize(event_id:, **attrs)
        # Assigned before super: IncomingMessage#initialize freezes the object,
        # so nothing can be written to it afterwards.
        @event_id = event_id
        super(**attrs)
      end
    end
  end
end
