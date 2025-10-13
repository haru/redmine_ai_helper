# frozen_string_literal: true

module AiHelper
  module Streaming
    extend ActiveSupport::Concern

    private

    def prepare_streaming_headers
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache"
      response.headers["Connection"] = "keep-alive"
    end

    def write_chunk(data)
      response.stream.write("data: #{data.to_json}\n\n")
    end

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
