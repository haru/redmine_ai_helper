# frozen_string_literal: true

# Namespace for concerns shared by AI helper controllers.
module AiHelper
  # Mixin that encapsulates Server-Sent Events (SSE) helpers for streaming LLM responses.
  module Streaming
    extend ActiveSupport::Concern

    private

    # Prepare headers required for SSE streaming.
    #
    # @return [void]
    def prepare_streaming_headers
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"
    end

    # Emit a JSON payload chunk over the SSE stream.
    #
    # @param data [Hash] payload to serialize and write.
    # @return [void]
    def write_chunk(data)
      response.stream.write("data: #{data.to_json}\n\n")
    end

    # Stream a full LLM response using SSE, yielding a proc to the caller for incremental content.
    #
    # @param close_stream [Boolean] whether to close the SSE stream after completion.
    # @yieldparam stream_proc [Proc] block to call with incremental response fragments.
    # @return [void]
    def stream_llm_response(close_stream: true, &block)
      prepare_streaming_headers

      response_id = "chatcmpl-#{SecureRandom.hex(12)}"

      write_chunk({
        id: response_id,
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "gpt-3.5-turbo-0613",
        choices: [{
          index: 0,
          delta: {
            role: "assistant",
          },
          finish_reason: nil,
        }],
      })

      stream_proc = Proc.new do |content|
        write_chunk({
          id: response_id,
          object: "chat.completion.chunk",
          created: Time.now.to_i,
          model: "gpt-3.5-turbo-0613",
          choices: [{
            index: 0,
            delta: {
              content: content,
            },
            finish_reason: nil,
          }],
        })
      end

      block.call(stream_proc)

      write_chunk({
        id: response_id,
        object: "chat.completion.chunk",
        created: Time.now.to_i,
        model: "gpt-3.5-turbo-0613",
        choices: [{
          index: 0,
          delta: {},
          finish_reason: "stop",
        }],
      })
    ensure
      response.stream.close if close_stream
    end
  end
end
