require "langfuse"
require "redmine_ai_helper/util/config_file"

module RedmineAiHelper
  # Langfuse observability utilities for LLM call tracking and monitoring.
  module LangfuseUtil
    # Wrapper for Langfuse.
    class LangfuseWrapper

      # @param input [String] The input string to be processed.
      def initialize(input:)
        config_yml = RedmineAiHelper::Util::ConfigFile.load_config[:langfuse]
        @enabled = false
        if config_yml
          Langfuse.configure do |config|
            config.public_key = config_yml[:public_key]
            config.secret_key = config_yml[:secret_key]
            config.host = config_yml[:endpoint] || "https://us.cloud.langfuse.com"
            config.debug = config_yml[:debug] || false
          end
          @trace = Langfuse.trace(
            name: "ai_helper",
            user_id: User.current.login,
            input: input,
            metadata: { source: "#{Setting.protocol}:#{Setting.host_name}" },
          )
          @enabled = true
        end
      end

      # @return [Boolean] Whether Langfuse is enabled or not.
      def enabled?
        return false if ENV["RAILS_ENV"] == "test"
        @enabled
      end

      # List of spans.
      # Represents the parent-child relationship of Langfuse spans.
      # The first element in the array is the most parent, and the last element is the currently active span.
      # @return [Array] The list of spans.
      def spans
        @spans ||= []
      end

      # Returns the current span.
      # @return [Span] The current span.
      def current_span
        spans.last
      end

      # @param name [String] The name of the span.
      # @param input [String] The input string to be processed.
      # @return [SpanWrapper] The SpanWrapper object.
      def create_span(name:, input:)
        return unless enabled?
        parent_span_id = current_span&.span&.id
        span = SpanWrapper.new(name: name, trace: @trace, input: input, parent_span_id: parent_span_id)
        spans << span if span
        span
      end

      # It finishes the current span and updates it with the output.
      # @param output [String] The output string.
      # @return [void]
      def finish_current_span(output:)
        return unless enabled?
        return unless current_span
        current_span.finish(output: output)
        spans.pop
      end

      # It finishes the trace and updates it with the output.

      # Updates the trace output.
      # @param output [String] The output to set on the trace.
      # @return [void]
      def update_trace_output(output:)
        return unless enabled?
        return unless @trace
        # Langfuse SDK has no update_trace method; trace-create with existing ID
        # performs an upsert, updating only the provided fields.
        Langfuse.trace(id: @trace.id, output: output)
      end

      def flush(output: nil)
        update_trace_output(output: output) if output
        Langfuse.flush
      end
    end

    # Wrapper for Langfuse span
    class SpanWrapper
      attr_reader :span, :trace

      # @param name [String] The name of the span.
      # @param trace [Trace] The trace object.
      # @param input [String] The input string to be processed.
      # @param parent_span_id [String] The parent span ID.
      # @return [SpanWrapper] The SpanWrapper object.
      def initialize(name:, trace:, input:, parent_span_id: nil)
        @trace = trace
        return unless @trace
        @span = Langfuse.span(
          name: name,
          trace_id: trace.id,
          input: { query: input },
          parent_observation_id: parent_span_id,
        )
      end

      # It finishes the span and updates it with the output.
      # @param output [String] The output string to be processed.
      # @return [void]
      # @note This method updates the span with the output and ends the span.
      def finish(output:)
        return unless @span
        @span.output = { processed_result: output }
        @span.end_time = Time.now.utc
        Langfuse.update_span(@span)
      end

      # creates a generation object.
      # @param name [String] The name of the generation.
      # @param messages [Array] The messages to be processed.
      # @param model [String] The model to be used.
      # @param temperature [Float] The temperature to be used.
      # @param max_tokens [Integer] The maximum number of tokens to be used.
      # @return [GenerationWrapper] The GenerationWrapper object.
      def create_generation(name:, messages:, model:, temperature: nil, max_tokens: nil)
        return unless @span

        GenerationWrapper.new(
          name: name,
          span: @span,
          messages: messages,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
        )
      end
    end

    # Wrapper for Langfuse generation
    class GenerationWrapper
      # @param name [String] The name of the generation.
      # @param span [Span] The span object.
      # @param messages [Array] The messages to be processed.
      # @param model [String] The model to be used.
      # @param temperature [Float] The temperature to be used.
      # @param max_tokens [Integer] The maximum number of tokens to be used.
      # @return [GenerationWrapper] The GenerationWrapper object.
      # @note This method creates a generation object and initializes it with the provided parameters.
      def initialize(name:, span:, messages:, model:, temperature: nil, max_tokens: nil)
        return unless span
        @generation = Langfuse.generation(
          name: name,
          trace_id: span.trace_id,
          parent_observation_id: span.id,
          model: model,
          model_parameters: {
            temperature: temperature,
            max_tokens: max_tokens,
          },
          input: messages,
        )
      end

      # It finishes the generation and updates it with the output.
      # @param output [String] The output string to be processed.
      # @param usage [Usage] The usage object to be processed.
      # @return [void]
      def finish(output:, usage:)
        return unless @generation
        @generation.output = output
        @generation.usage = Langfuse::Models::Usage.new(
          prompt_tokens: usage[:prompt_tokens],
          completion_tokens: usage[:completion_tokens],
          total_tokens: usage[:total_tokens],
        )
        Langfuse.update_generation(@generation)
      end
    end
  end
end
