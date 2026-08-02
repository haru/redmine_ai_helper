# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/incoming_message"
require "redmine_ai_helper/chat_channel/issue_link_formatter"
require "redmine_ai_helper/chat_channel/message_handler"

module RedmineAiHelper
  module ChatChannel
    # Abstract base class for chat tool adapters. Subclasses are registered
    # automatically on inheritance (same pattern as BaseAgent) and only need
    # to implement the tool-specific interface: channel_type, start, stop
    # and send_message.
    class BaseAdapter
      include RedmineAiHelper::Logger

      class << self
        # Adapter subclasses collected by the inherited hook. channel_type is
        # resolved lazily in .adapters because it is not yet defined when
        # inherited fires (the subclass body has not been evaluated).
        # @return [Array<Class>]
        def registered_subclasses
          @registered_subclasses ||= []
        end

        # Registered adapter classes keyed by channel_type.
        # @return [Hash{String => Class}]
        def adapters
          BaseAdapter.registered_subclasses.index_by(&:channel_type)
        end

        # Automatically registers subclasses (same pattern as BaseAgent).
        # @param subclass [Class] The inheriting adapter class
        # @return [void]
        def inherited(subclass)
          super
          BaseAdapter.registered_subclasses << subclass
        end

        # Adapter identifier matching the channel_type column of bindings,
        # channel conversations and adapter settings.
        # @return [String]
        def channel_type
          raise NotImplementedError, "#{name} must implement .channel_type"
        end

        # Setting columns that must be present for the integration to run.
        # @return [Array<Symbol>]
        def required_setting_fields
          []
        end

        # Pops from queue, waiting up to timeout seconds for a value.
        # Queue#pop's timeout: keyword was added in Ruby 3.2, but this plugin
        # still supports Ruby 3.1, so waiting is implemented by polling a
        # non-blocking pop instead.
        # @param queue [Queue] the queue to pop from
        # @param timeout [Numeric] seconds to wait before giving up
        # @return [Object, nil] the popped value, or nil if the timeout elapsed
        def timed_queue_pop(queue, timeout)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            return queue.pop(true)
          rescue ThreadError
            remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            return nil if remaining <= 0

            sleep [ remaining, 0.05 ].min
          end
        end
      end

      # The gateway this adapter dispatches messages through. Set by the
      # gateway when it starts the adapter; nil when the adapter runs
      # standalone (e.g. in tests).
      # @return [Gateway, nil]
      attr_accessor :dispatcher

      # The tool-independent message handler bound to this adapter.
      # @return [MessageHandler]
      def handler
        @handler ||= MessageHandler.new(self)
      end

      # Hands a normalized message over for processing. When attached to a
      # gateway the message is queued for the single worker thread; otherwise
      # it is handled inline.
      # @param message [IncomingMessage] the normalized message
      # @return [void]
      def dispatch(message)
        if dispatcher
          dispatcher.enqueue(self, message)
        else
          handler.handle(message)
        end
      end

      # The settings row for this adapter.
      # @return [AiHelperChatAdapterSetting]
      def settings
        AiHelperChatAdapterSetting.for_channel(channel_type)
      end

      # Whether the integration is enabled and all required setting fields
      # are present.
      # @return [Boolean]
      def enabled?
        setting = settings
        return false unless setting.enabled

        self.class.required_setting_fields.all? { |field| setting.send(field).present? }
      end

      # Instance-level logger access for adapters.
      # @return [RedmineAiHelper::CustomLogger]
      delegate :ai_helper_logger, to: :class

      # Adapter identifier (delegates to the class-level declaration).
      # @return [String]
      delegate :channel_type, to: :class

      # Connects to the external tool and blocks while receiving events.
      # @return [void]
      def start
        raise NotImplementedError, "#{self.class.name} must implement #start"
      end

      # Closes the connection and lets #start return.
      # @return [void]
      def stop
        raise NotImplementedError, "#{self.class.name} must implement #stop"
      end

      # Posts a reply into the given thread.
      # @param channel_id [String] Channel identifier
      # @param thread_key [String] Thread identifier
      # @param text [String] Reply body
      # @return [void]
      def send_message(channel_id:, thread_key:, text:)
        raise NotImplementedError, "#{self.class.name} must implement #send_message"
      end

      # The link format for this adapter. Returns PLAIN by default so that
      # adapters that do not declare a format still produce link-safe output.
      # @return [IssueLinkFormatter::Format]
      def issue_link_format
        IssueLinkFormatter::PLAIN
      end

      # Adjusts a cut position so that it does not fall inside a link syntax
      # produced by the adapter's format. Returns the adjusted cut or the
      # original cut when no link spans the boundary. Returns the original
      # cut when the adjusted position would be 0 (safety valve against
      # infinite loops in pathological cases).
      # @param text [String] The full text being split (not the slice)
      # @param cut [Integer] The proposed cut position
      # @return [Integer] The adjusted cut position
      def link_safe_cut(text, cut)
        text.scan(issue_link_format.pattern) do
          match_start = Regexp.last_match.begin(0)
          match_end = Regexp.last_match.end(0)
          break if match_start >= cut

          return match_start if match_start.positive? && match_end > cut
        end
        cut
      end

      # Whether the adapter can retrieve past messages from the chat tool.
      # History retrieval is optional: adapters that leave this at false keep
      # working through the unchanged core, the only difference being that
      # answers are generated without surrounding context (FR-010).
      # @return [Boolean]
      def supports_history?
        false
      end

      # Messages posted in a thread, in ascending (oldest first) order. No
      # count or age limit is applied.
      # @param channel_id [String] Parent channel identifier
      # @param thread_key [String] Thread identifier (same format as elsewhere)
      # @param after [String, nil] Import cursor; only messages after this
      #   external message id are returned. nil returns the whole thread.
      # @return [Array<HistoryMessage>]
      def fetch_thread_history(channel_id:, thread_key:, after: nil)
        raise NotImplementedError, "#{self.class.name} must implement #fetch_thread_history"
      end

      # Top-level messages of a channel (or DM), in ascending order.
      # @param channel_id [String] Channel identifier (DM channel id for DMs)
      # @param before [String, nil] Only messages before this external message
      #   id are returned, which excludes the mention itself
      # @param since [Time] Only messages posted at or after this time
      # @param limit [Integer] Maximum number of messages, counted from the
      #   most recent one
      # @return [Array<HistoryMessage>]
      def fetch_channel_history(channel_id:, before:, since:, limit:)
        raise NotImplementedError, "#{self.class.name} must implement #fetch_channel_history"
      end

      # Whether the given error is a fatal configuration/credential error
      # that the supervisor (systemd) must not retry. Defaults to false;
      # adapters override to classify their own credential errors so ADR-006
      # ("credential problems are never retried") holds at the process level.
      # @param _error [Exception] the error raised by the adapter
      # @return [Boolean]
      def fatal_config_error?(_error)
        false
      end
    end
  end
end
