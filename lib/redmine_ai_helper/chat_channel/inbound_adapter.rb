# frozen_string_literal: true

require "json"
require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/base_adapter"

module RedmineAiHelper
  module ChatChannel
    # Abstract base class for adapters that receive events by webhook rather
    # than an outgoing connection (LINE, Microsoft Teams, ...). #start polls
    # the persistent queue table (+ai_helper_inbound_events+) that
    # +AiHelperChatWebhookController+ fills, instead of opening a socket
    # (research.md R-002/R-003, contracts/inbound_adapter.md).
    class InboundAdapter < BaseAdapter
      # Interval between polls of the pending queue, in seconds (SC-005).
      POLL_INTERVAL_SECONDS = 2
      # Events claimed more than this many seconds after being received are
      # discarded unanswered instead of processed (FR-008a).
      FRESHNESS_LIMIT_SECONDS = 120
      # How long a row is kept, for deduplication, before it becomes eligible
      # for deletion (FR-009).
      RETENTION_DAYS = 7
      # Minimum interval between two retention cleanups.
      CLEANUP_INTERVAL_SECONDS = 3600
      # Maximum number of pending rows fetched per poll.
      POLL_BATCH_SIZE = 20

      class << self
        # Capability declaration read by the settings UI to decide whether to
        # display the webhook URL to register with the external service
        # (R-010).
        # @return [Boolean]
        def inbound?
          true
        end
      end

      # Verifies the authenticity of a webhook request (FR-002). No default
      # implementation is provided: unlike an outgoing-connection adapter, an
      # inbound adapter has no other proof that a request is genuine, so
      # skipping verification is never an acceptable fallback.
      # @param _request [ActionDispatch::Request] read +raw_post+ for the
      #   exact bytes a signature is computed over, never the parsed body
      # @return [Boolean] whether the request is authentic
      def verify_request(_request)
        raise NotImplementedError, "#{self.class.name} must implement #verify_request"
      end

      # Converts a verified request into zero or more normalized events
      # (FR-005). Must never yield the bot's own messages or carry speaker
      # identity (FR-003).
      # @param _request [ActionDispatch::Request]
      # @return [Array<Hash>] event hashes; see contracts/inbound_adapter.md
      def parse_events(_request)
        raise NotImplementedError, "#{self.class.name} must implement #parse_events"
      end

      # Answers a service's webhook registration handshake (FR-013). Returns
      # nil for a normal event delivery; this default covers every service
      # that has no such handshake.
      # @param _request [ActionDispatch::Request]
      # @return [Hash, nil] +{status:, content_type:, body:}+, or nil
      def challenge_response(_request)
        nil
      end

      # Polls the pending queue until #stop is called (BaseAdapter contract).
      # Runs under a checked-out connection because this thread is not a
      # Rails request thread.
      # @return [void]
      def start
        clear_stop_flag
        @connection_ended = Queue.new
        until stopped?
          ActiveRecord::Base.connection_pool.with_connection { poll_cycle }
          self.class.timed_queue_pop(@connection_ended, POLL_INTERVAL_SECONDS)
        end
      end

      # Reply metadata saved with the most recently claimed event of the
      # given thread (R-008). The gateway's worker is single-threaded, so
      # this always resolves to the event currently being answered.
      # @param thread_key [String]
      # @return [Hash, nil]
      def reply_metadata_for(thread_key:)
        event = AiHelperInboundEvent.where(channel_type: channel_type, thread_key: thread_key, status: "processed")
                                     .order(received_at: :desc).first
        return nil if event&.reply_metadata.blank?

        JSON.parse(event.reply_metadata)
      end

      private

      # One polling cycle: claim and dispatch due events, then run retention
      # cleanup if it is due.
      # @return [void]
      def poll_cycle
        AiHelperInboundEvent.pending_for(channel_type, limit: POLL_BATCH_SIZE).each do |event|
          process_event(event)
        end
        purge_expired_rows_if_due
      end

      # Claims one event and either discards it as stale or dispatches it.
      # An exception here is logged with a full backtrace and does not stop
      # the loop: one bad event must not take down every other pending event.
      # @param event [AiHelperInboundEvent]
      # @return [void]
      def process_event(event)
        return unless event.claim

        if event.expired_by?(FRESHNESS_LIMIT_SECONDS)
          event.expire!
          ai_helper_logger.info "#{channel_type}: discarded stale event #{event.event_key} received at #{event.received_at}"
          return
        end

        dispatch(event.to_incoming_message)
      rescue => e
        ai_helper_logger.error "#{channel_type}: error while processing inbound event #{event.event_key}: #{e.full_message}"
      end

      # Deletes rows past the retention period, at most once per
      # CLEANUP_INTERVAL_SECONDS (FR-009 / R-009).
      # @return [void]
      def purge_expired_rows_if_due
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return if @last_purge_at && (now - @last_purge_at) < CLEANUP_INTERVAL_SECONDS

        AiHelperInboundEvent.purge_old(channel_type, before: RETENTION_DAYS.days.ago)
        @last_purge_at = now
      end
    end
  end
end
