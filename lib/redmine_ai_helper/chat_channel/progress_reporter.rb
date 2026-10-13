# frozen_string_literal: true

require "redmine_ai_helper/logger"

module RedmineAiHelper
  module ChatChannel
    # Shows the progress of one question in the chat tool: a single message
    # that is posted with the first progress line, rewritten as more lines
    # arrive and deleted when the question has been answered.
    #
    # Instances are handed to the LLM layer as a +progress_proc+ (anything that
    # responds to #call). Failures of the chat tool's API are logged and never
    # raised, so a progress message that cannot be shown never costs the
    # answer. This is a deliberate exception to the no-fallback rule (FR-006,
    # docs/adr/054-chat-channel-progress-message.md), limited to this
    # auxiliary display: only the adapter calls are rescued.
    class ProgressReporter
      include RedmineAiHelper::Logger

      # Reference to a posted progress message.
      class Handle
        # @return [String] the channel the message was actually posted in
        attr_reader :channel_id
        # @return [String] the chat tool's id of the message
        attr_reader :message_id

        # @param channel_id [String] non-empty channel identifier
        # @param message_id [String] non-empty message identifier
        # @raise [ArgumentError] when either value is not a non-empty String
        def initialize(channel_id:, message_id:)
          { channel_id: channel_id, message_id: message_id }.each do |name, value|
            raise ArgumentError, "#{name} must be a non-empty String" unless value.is_a?(String) && !value.empty?
          end
          @channel_id = channel_id
          @message_id = message_id
          freeze
        end
      end

      delegate :ai_helper_logger, to: :class

      # @param adapter [BaseAdapter] the adapter the question arrived through
      # @param message [IncomingMessage] the question being processed; its
      #   channel and thread tell where the progress message goes
      def initialize(adapter:, message:)
        @adapter = adapter
        @message = message
        @lines = []
        @handle = nil
        @disabled = !adapter.supports_progress?
        @finished = false
      end

      # Keeps the reporter's adapter and message out of the log line that
      # prints Llm#chat's options.
      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      # Adds one progress line and shows all lines so far: the first line is
      # posted, later lines rewrite the same message. Does nothing when the
      # adapter has no progress support, the first post failed or #finish
      # has run.
      # @param text [String] the progress text; trailing newlines are dropped
      #   and blank text is ignored
      # @return [void]
      # @raise [ArgumentError] when +text+ is not a String
      def call(text)
        raise ArgumentError, "progress text must be a String" unless text.is_a?(String)
        return if @disabled || @finished

        line = text.sub(/\n+\z/, "")
        return if line.strip.empty?

        @lines << line
        shown = fit(@lines)
        if @handle
          guarded("update") { @adapter.update_progress(handle: @handle, text: shown) }
        else
          posted = guarded("post") do
            @handle = @adapter.post_progress(channel_id: @message.channel_id, thread_key: @message.thread_key, text: shown)
          end
          @disabled = true unless posted
        end
      end

      # Deletes the posted progress message, if any. Call it once the answer
      # (or the error notice) has been posted. Later calls do nothing.
      # @return [void]
      def finish
        return if @finished

        @finished = true
        return if @disabled || @handle.nil?

        guarded("delete") { @adapter.delete_progress(handle: @handle) }
      end

      private

      # The lines joined into one text that fits the adapter's limit: the
      # oldest lines go first, and a last line that alone is too long is cut.
      # @param lines [Array<String>]
      # @return [String]
      def fit(lines)
        max = @adapter.max_message_length
        kept = lines.dup
        kept.shift while kept.size > 1 && kept.join("\n").length > max
        kept.join("\n").truncate(max)
      end

      # Runs one adapter call. A StandardError is logged and reported as a
      # failure instead of being raised (FR-006).
      # @param action [String] "post", "update" or "delete", for the log
      # @return [Boolean] whether the call succeeded
      def guarded(action)
        yield
        true
      rescue StandardError => e
        ai_helper_logger.error "chat channel: failed to #{action} progress message on " \
                               "#{@message.channel_type} thread #{@message.thread_key}: #{e.full_message}"
        false
      end
    end
  end
end
