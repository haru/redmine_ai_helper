# frozen_string_literal: true

require "redmine_ai_helper/logger"

module RedmineAiHelper
  module ChatChannel
    # Shows the progress of one question in the chat tool: a single message
    # that is posted with the first progress line and given an hourglass
    # reaction, rewritten as more lines arrive and deleted when the question
    # has been answered.
    #
    # A reporter moves idle -> posted -> finished. It is disabled from the
    # start when the adapter has no progress support, and after a failed first
    # post; a disabled reporter does nothing.
    #
    # Instances are handed to the LLM layer as a +progress_proc+ (anything that
    # responds to #call). Failures of the chat tool's API are logged instead of
    # raised, so a progress message that cannot be shown never costs the
    # answer. This is a deliberate exception to the no-fallback rule (073 FR-006,
    # docs/adr/054-chat-channel-progress-message.md), limited to this
    # auxiliary display: only the errors the adapter declares in
    # BaseAdapter#progress_errors (the chat tool's API and network failures)
    # are rescued; bugs in the adapter or in this class surface.
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
          @channel_id = -channel_id
          @message_id = -message_id
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
        @state = adapter.supports_progress? ? :idle : :disabled
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
        return if %i[disabled finished].include?(@state)

        line = text.sub(/\n+\z/, "")
        return if line.strip.empty?

        @lines << line
        shown = fit(@lines)
        if @handle
          guarded("update") { @adapter.update_progress(handle: @handle, text: shown) }
        else
          posted = guarded("post") do
            handle = @adapter.post_progress(channel_id: @message.channel_id, thread_key: @message.thread_key, text: shown)
            raise TypeError, "#{@adapter.class.name}#post_progress must return a ProgressReporter::Handle" unless handle.is_a?(Handle)

            @handle = handle
          end
          @state = posted ? :posted : :disabled
          guarded("mark") { @adapter.mark_progress(handle: @handle) } if posted
        end
      end

      # Deletes the posted progress message, if any. Call it once the answer
      # (or the error notice) has been posted. Later calls do nothing.
      # @return [void]
      def finish
        return if @state == :finished

        @state = :finished
        return unless @handle

        guarded("delete") { @adapter.delete_progress(handle: @handle) }
      end

      private

      # The lines joined into one text that fits the adapter's limit: the
      # oldest lines go first, and a last line that alone is too long is cut.
      # @param lines [Array<String>]
      # @return [String]
      def fit(lines)
        max = @adapter.max_message_length
        raise ArgumentError, "max_message_length must be an Integer of at least 3" unless max.is_a?(Integer) && max >= 3

        kept = lines.dup
        kept.shift while kept.size > 1 && kept.join("\n").length > max
        kept.join("\n").truncate(max)
      end

      # Runs one adapter call. An error listed in the adapter's
      # #progress_errors is logged and reported as a failure instead of being
      # raised (073 FR-006); any other error is raised.
      # @param action [String] "post", "mark", "update" or "delete", for the log
      # @return [Boolean] whether the call succeeded
      def guarded(action)
        yield
        true
      rescue *@adapter.progress_errors => e
        target = @handle ? " #{@handle.message_id} (channel #{@handle.channel_id})" : ""
        ai_helper_logger.error "chat channel: failed to #{action} progress message#{target} on " \
                               "#{@message.channel_type} thread #{@message.thread_key}: #{e.full_message}"
        false
      end
    end
  end
end
