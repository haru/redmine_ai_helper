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

      # Reconnect when no frame of any type has been received for this long.
      # Adapters that can derive a better bound from the protocol override
      # #receive_timeout_seconds (contract C-2).
      DEFAULT_RECEIVE_TIMEOUT_SECONDS = 30
      # Upper bound of the exponential reconnect backoff.
      MAX_BACKOFF_SECONDS = 60

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

      # Initializes the state every adapter carries for its whole lifetime.
      # The send mutex belongs to the adapter rather than to one connection: it
      # must survive a reconnect so a close frame on the old socket cannot
      # overlap a send on the new one (INV-4). The last receive time is reset
      # per connection by #touch_received, but it lives here so an adapter that
      # never connects still has a defined value. Adapters that do not open a
      # socket simply never use either of them (INV-8).
      # @return [void]
      def initialize
        @stopped = false
        @backoff = 1
        @send_mutex = Mutex.new
        # Not "now": never having received a frame must count as stale, so the
        # monitor loop reconnects instead of waiting out a full timeout (INV-1).
        @last_received_at = 0.0
      end

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

      # Closes the connection and lets #start return: raises the stop flag,
      # wakes the monitor loop and closes the socket under the send mutex
      # (C-5.5). Adapters that hold no socket inherit this unchanged - the
      # close is a no-op when @ws was never assigned (C-3.8 / INV-8).
      # @return [void]
      def stop
        @stopped = true
        connection_ended!
        close_socket
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

      protected

      # Dispatches one received WebSocket frame by type. Runs on the
      # connection's receive thread, so no exception may escape into the
      # gem's own handler where it would never reach ai_helper_logger.
      # +client+ is the connection the frame arrived on rather than the
      # adapter's @ws, which is assigned only after
      # WebSocket::Client::Simple.connect returns: a frame arriving in that
      # short window would otherwise be unanswerable (INV-6).
      # @param client [WebSocket::Client::Simple::Client] the connection the frame arrived on
      # @param msg [#type, #data, #code] the received frame
      # @return [void]
      def handle_frame(client, msg)
        touch_received
        case msg.type
        when :ping
          # RFC 6455: a pong must carry the ping's application data verbatim.
          # No validation, transformation or discarding of the payload.
          send_frame(client, msg.data, type: :pong)
        when :text
          handle_text_frame(client, msg.data)
        when :close
          handle_close_frame(msg.code)
        end
      rescue => e
        ai_helper_logger.error "#{channel_type}: error while handling frame: #{e.full_message}"
        # A credential error must not be turned into a reconnect: #start would
        # see an established connection, skip the backoff and retry into the
        # same broken credentials forever. It is carried over to the connecting
        # thread instead, which raises it out of #start (C-1.9 / ADR-006).
        if fatal_config_error?(e)
          fatal_error!(e)
        else
          connection_ended!
        end
      end

      # Handles one text frame in the adapter's own protocol.
      # @param _client [WebSocket::Client::Simple::Client] the connection the frame arrived on
      # @param _data [String] the frame payload
      # @return [void]
      def handle_text_frame(_client, _data)
        raise NotImplementedError, "#{self.class.name} must implement #handle_text_frame"
      end

      # Reacts to a close frame. Adapters that classify close codes override
      # this and delegate the common part back here with super.
      # @param code [Integer, nil] the WebSocket close code
      # @return [void]
      def handle_close_frame(code)
        ai_helper_logger.info "#{channel_type}: close frame received (code #{code || "none"})"
        connection_ended!
      end

      # Records the current time as the last time any frame was received,
      # regardless of type (INV-2).
      # @return [void]
      def touch_received
        @last_received_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Waits for the connection to end: either the remote side signals it (a
      # close frame, a socket error) or no frame of any type has been received
      # within #receive_timeout_seconds. Liveness is judged only by what
      # arrives, never by counting answers to something this loop sent
      # (ADR-013, extended to every adapter by ADR-014). Waits until the
      # earlier of the receive deadline and the next scheduled action, and
      # recomputes both whenever it wakes up without an end notification, since
      # a frame may have arrived while it was waiting.
      # @return [void]
      def watchdog_loop
        until stopped? || @reconnect_requested
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          elapsed = now - @last_received_at
          remaining = receive_timeout_seconds - elapsed
          if remaining <= 0
            ai_helper_logger.warn "#{channel_type}: no frame received for #{elapsed.round(1)}s, reconnecting"
            request_reconnect
            break
          end
          # compact drops the nil #next_scheduled_action_in returns when the
          # adapter has nothing scheduled, leaving the receive deadline alone.
          wait = [ remaining, next_scheduled_action_in ].compact.min
          break if self.class.timed_queue_pop(@connection_ended, wait)

          perform_scheduled_action
        end
      end

      # Seconds without any received frame after which the connection counts
      # as dead. Evaluated on every pass of #watchdog_loop, so an adapter may
      # return a value that only becomes known mid-connection.
      # @return [Numeric]
      def receive_timeout_seconds
        DEFAULT_RECEIVE_TIMEOUT_SECONDS
      end

      # Seconds until the adapter's next scheduled action, or nil when it has
      # none. Bounds how long #watchdog_loop sleeps in one go.
      # @return [Numeric, nil]
      def next_scheduled_action_in
        nil
      end

      # Runs the adapter's scheduled action, if any. Called by
      # #watchdog_loop whenever a wait ends without the connection ending.
      # @return [void]
      def perform_scheduled_action
        # Adapters with nothing to send on a schedule leave this empty.
      end

      # Sends one frame through +client+, serialized against every other send
      # on this connection via @send_mutex (INV-3).
      # @param client [WebSocket::Client::Simple::Client, nil] the connection to send on
      # @param data [String] the frame payload
      # @param type [Symbol] the frame type
      # @return [void]
      def send_frame(client, data, type: :text)
        @send_mutex.synchronize { client&.send(data, type: type) }
      end

      # Closes the current socket, if any, under @send_mutex so the close
      # frame is serialized against every other send on the connection (C-3.4),
      # and ignoring the usual close-time IO errors.
      # @return [void]
      def close_socket
        socket = @ws
        @ws = nil
        @send_mutex.synchronize { socket&.close }
      rescue IOError, SystemCallError => e
        ai_helper_logger.debug "#{channel_type}: error while closing socket: #{e.message}"
      end

      # Asks the listen loop to end so #start reconnects with a fresh URL.
      # @return [void]
      def request_reconnect
        @reconnect_requested = true
        connection_ended!
      end

      # Signals that this connection is over, whatever the reason (a close
      # frame, a socket error, a requested reconnect, #stop): the monitor loop
      # stops waiting and #listen returns.
      # @return [void]
      def connection_ended!
        @connection_ended&.push(true)
      end

      # Records an error that must terminate the adapter instead of leading to
      # a reconnect, and ends the connection. The receive thread cannot raise
      # into #start - the WebSocket gem would swallow the exception - so the
      # error is carried across through @fatal_close (C-1.9 / C-6.5.1).
      # @param error [Exception] the fatal error
      # @return [void]
      def fatal_error!(error)
        @fatal_close = error
        connection_ended!
      end

      # Re-raises the error captured by #fatal_error!, if any. Called by
      # #listen after the monitor loop returns, so the error reaches #start on
      # the connecting thread and terminates it without a retry (C-6.5.3).
      # @return [void]
      def raise_fatal_error!
        raise @fatal_close if @fatal_close
      end

      # A socket error occurred; end the connection so #start can retry.
      # @param error [Exception] the socket error
      # @return [void]
      def socket_errored(error)
        ai_helper_logger.error "#{channel_type}: websocket error: #{error.full_message}"
        connection_ended!
      end

      # Whether #stop has been called.
      # @return [Boolean]
      def stopped?
        @stopped
      end

      # Clears the stop flag so a stopped adapter can be started again. Called
      # at the top of #start; the flag itself is owned by BaseAdapter (C-5.1).
      # @return [void]
      def clear_stop_flag
        @stopped = false
      end

      # Returns the current backoff delay and doubles it (capped).
      # @return [Integer] seconds to wait
      def next_backoff
        current = @backoff
        @backoff = [ @backoff * 2, MAX_BACKOFF_SECONDS ].min
        current
      end

      # Resets the backoff after a successful connection.
      # @return [void]
      def reset_backoff
        @backoff = 1
      end
    end
  end
end
