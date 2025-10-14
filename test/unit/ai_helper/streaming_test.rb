require File.expand_path("../../../test_helper", __FILE__)
require "json"
require "active_support/testing/time_helpers"

class AiHelper::StreamingTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers
  FakeStream = Struct.new(:writes, :closed) do
    def initialize
      super([], false)
    end

    def write(data)
      writes << data
    end

    def close
      self.closed = true
    end

    def closed?
      closed
    end
  end

  ResponseStub = Struct.new(:headers, :stream)

  class DummyContext
    include AiHelper::Streaming

    attr_reader :response, :stream

    def initialize
      @stream = FakeStream.new
      @response = ResponseStub.new({}, @stream)
    end
  end

  def setup
    super
    @fixed_time = Time.at(1_700_000_000)
    @fixed_hex = "fixedhexvaluefixedhexvalue"
  end

  def test_prepare_streaming_headers_sets_expected_values
    context = DummyContext.new

    context.send(:prepare_streaming_headers)

    assert_equal "text/event-stream", context.response.headers["Content-Type"]
    assert_equal "no-cache", context.response.headers["Cache-Control"]
    assert_equal "keep-alive", context.response.headers["Connection"]
  end

  def test_write_chunk_formats_server_sent_event_payload
    context = DummyContext.new

    context.send(:write_chunk, { foo: "bar" })

    assert_equal 1, context.stream.writes.size
    assert_equal "data: {\"foo\":\"bar\"}\n\n", context.stream.writes.first
  end

  def test_stream_llm_response_streams_chunks_and_closes_stream
    context = DummyContext.new

    with_fixed_random do
      travel_to @fixed_time do
        context.send(:stream_llm_response) do |stream_proc|
          stream_proc.call("Hello Redmine")
        end
      end
    end

    assert_equal "text/event-stream", context.response.headers["Content-Type"]
    assert_equal 3, context.stream.writes.size

    initial_chunk = parse_chunk(context.stream.writes[0])
    streamed_chunk = parse_chunk(context.stream.writes[1])
    final_chunk = parse_chunk(context.stream.writes[2])

    expected_id = "chatcmpl-#{@fixed_hex}"

    assert_equal expected_id, initial_chunk["id"]
    assert_equal @fixed_time.to_i, initial_chunk["created"]
    assert_equal "assistant", initial_chunk["choices"].first["delta"]["role"]

    assert_equal expected_id, streamed_chunk["id"]
    assert_equal "Hello Redmine", streamed_chunk["choices"].first["delta"]["content"]

    assert_equal expected_id, final_chunk["id"]
    assert_equal({}, final_chunk["choices"].first["delta"])
    assert_equal "stop", final_chunk["choices"].first["finish_reason"]

    assert context.stream.closed?
  end

  def test_stream_llm_response_does_not_close_stream_when_requested
    context = DummyContext.new

    with_fixed_random do
      travel_to @fixed_time do
        context.send(:stream_llm_response, close_stream: false) do |_stream_proc|
          # no-op
        end
      end
    end

    refute context.stream.closed?
  end

  def test_stream_llm_response_closes_stream_on_error
    context = DummyContext.new

    assert_raises RuntimeError do
      with_fixed_random do
        travel_to @fixed_time do
          context.send(:stream_llm_response) do |_stream_proc|
            raise "boom"
          end
        end
      end
    end

    assert context.stream.closed?
    assert_equal 1, context.stream.writes.size, "initial chunk should be written before the error"
  end

  private

  def with_fixed_random
    SecureRandom.stubs(:hex).with(12).returns(@fixed_hex)
    yield
  ensure
    SecureRandom.unstub(:hex)
  end

  def parse_chunk(chunk)
    json = chunk.sub(/^data: /, "").sub(/\n\n\z/, "")
    JSON.parse(json)
  end
end
