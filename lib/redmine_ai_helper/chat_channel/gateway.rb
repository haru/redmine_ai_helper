# frozen_string_literal: true

require "redmine_ai_helper/logger"
require "redmine_ai_helper/chat_channel/base_adapter"

module RedmineAiHelper
  # Abstraction layer connecting external chat tools (Slack etc.) to the AI
  # helper: adapters, the shared message handler and the gateway process.
  module ChatChannel
    # Resident gateway process: starts every enabled adapter in its own
    # receive thread and serializes all message processing through a single
    # worker thread, so each question runs under the configured execution
    # account (service account) without any concurrent permission context
    # (research.md R-003).
    class Gateway
      include RedmineAiHelper::Logger

      # Raised when the gateway cannot start (or an adapter terminated on a
      # credential/configuration error). The supervisor (systemd) must not
      # retry these — the operator has to fix the configuration first
      # (ADR-006: "credential problems are never retried"). Rake rescues
      # this and exits 0 so Restart=on-failure does not loop.
      class ConfigurationError < StandardError; end

      # Upper bound of queued messages awaiting the worker.
      QUEUE_SIZE = 100

      # Internal marker asking the worker loop to finish after draining.
      SHUTDOWN = :shutdown

      def initialize
        @queue = SizedQueue.new(QUEUE_SIZE)
        @shutdown_requested = false
      end

      # Queues a message received by an adapter thread for the worker.
      # Silently drops messages after shutdown is requested to prevent
      # orphaned items that would never be processed.
      # @param adapter [BaseAdapter] the adapter the message arrived on
      # @param message [IncomingMessage] the normalized message
      # @return [void]
      def enqueue(adapter, message)
        return if @shutdown_requested
        @queue << [ adapter, message ]
      end

      # Starts all enabled adapters and blocks processing messages until
      # #shutdown is called (SIGTERM/SIGINT). Raises ConfigurationError when
      # no adapter is enabled: the gateway never idles without a configured
      # integration, and configuration problems must not be retried.
      # @return [void]
      def run
        @adapters = build_enabled_adapters
        if @adapters.empty?
          ai_helper_logger.error "gateway: no enabled chat channel adapter found"
          raise ConfigurationError, "No chat channel adapter is enabled. Configure one in the AI helper settings."
        end

        install_signal_handlers
        ai_helper_logger.info "gateway: starting adapters: #{@adapters.map(&:channel_type).join(", ")}"
        threads = @adapters.map { |adapter| start_adapter_thread(adapter) }
        worker_loop
        threads.each { |thread| thread.join(5) }
        ai_helper_logger.info "gateway: stopped"
        raise @adapter_error if @adapter_error
      end

      # Stops all adapters and lets the worker drain the queue and exit.
      # @return [void]
      def shutdown
        return if @shutdown_requested
        @shutdown_requested = true
        ai_helper_logger.info "gateway: shutdown requested"
        (@adapters || []).each do |adapter|
          adapter.stop
        rescue => e
          ai_helper_logger.error "gateway: error stopping #{adapter.channel_type}: #{e.message}"
        end
        @queue << SHUTDOWN
      end

      private

      # Instantiates every registered adapter and keeps the enabled ones.
      # @return [Array<BaseAdapter>]
      def build_enabled_adapters
        BaseAdapter.adapters.values.map(&:new).select(&:enabled?)
      end

      # Runs one adapter's blocking receive loop in its own thread. A crashed
      # adapter takes the gateway down: errors must surface, not idle.
      # Configuration/credential errors are wrapped in ConfigurationError so
      # the supervisor can tell them apart from genuine crashes.
      def start_adapter_thread(adapter)
        adapter.dispatcher = self
        Thread.new do
          adapter.start
        rescue => e
          ai_helper_logger.error "gateway: adapter #{adapter.channel_type} terminated: #{e.full_message}"
          @adapter_error = adapter.fatal_config_error?(e) ? ConfigurationError.new(e.message) : e
          shutdown
        end
      end

      # Processes queued messages one at a time until shutdown, draining
      # whatever was queued before the shutdown marker. A single message
      # that escapes the handler's own rescue is logged here and skipped,
      # so the gateway never dies on a bad message.
      def worker_loop
        loop do
          item = @queue.pop
          break if item == SHUTDOWN

          adapter, message = item
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              adapter.handler.handle(message)
            end
            ai_helper_logger.info "gateway: processed message on #{adapter.channel_type} thread #{message.thread_key}"
          rescue => e
            ai_helper_logger.error "gateway: error processing message on #{adapter.channel_type}: #{e.full_message}"
          end
        end
      end

      # SIGTERM/SIGINT trigger a graceful shutdown. The handler body runs in
      # a new thread because trap context forbids blocking operations.
      def install_signal_handlers
        %w[TERM INT].each do |signal|
          Signal.trap(signal) { Thread.new { shutdown } }
        end
      end
    end
  end
end
