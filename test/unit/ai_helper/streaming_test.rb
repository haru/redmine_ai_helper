require File.expand_path("../../../test_helper", __FILE__)
require "json"
require "active_support/testing/time_helpers"
require "redmine_ai_helper/util/interactive_options_parser"

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

  def test_send_interactive_options_event_writes_sse_event_when_options_present
    context = DummyContext.new
    options = [{ label: "はい", value: "はい" }, { label: "いいえ", value: "いいえ" }]

    context.send(:send_interactive_options_event, options)

    assert_equal 1, context.stream.writes.size
    written = context.stream.writes.first
    assert_match(/\Aevent: interactive_options\n/, written)
    assert_match(/data: /, written)
    assert_match(/\n\n\z/, written)
    data_json = written.match(/data: (.+)\n\n/)[1]
    data = JSON.parse(data_json)
    assert_equal 2, data["choices"].length
    assert_equal "はい", data["choices"][0]["label"]
    assert_equal "いいえ", data["choices"][1]["label"]
  end

  def test_send_interactive_options_event_does_nothing_when_options_nil
    context = DummyContext.new

    context.send(:send_interactive_options_event, nil)

    assert_equal 0, context.stream.writes.size
  end

  def test_send_interactive_options_event_does_nothing_when_options_empty
    context = DummyContext.new

    context.send(:send_interactive_options_event, [])

    assert_equal 0, context.stream.writes.size
  end

  def test_stream_llm_response_calls_extract_options_on_full_content
    context = DummyContext.new
    content_with_options = "この課題を移動しますか？\n\n<!--AIHELPER_OPTIONS:{\"choices\":[{\"label\":\"はい\",\"value\":\"はい\"},{\"label\":\"いいえ\",\"value\":\"いいえ\"}]}-->"

    with_fixed_random do
      travel_to @fixed_time do
        context.send(:stream_llm_response) do |stream_proc|
          stream_proc.call(content_with_options)
        end
      end
    end

    # 3 data chunks + 1 interactive_options event
    assert_equal 4, context.stream.writes.size
    options_event = context.stream.writes.last
    assert_match(/\Aevent: interactive_options\n/, options_event)
  end

  def test_stream_llm_response_does_not_send_options_event_when_no_block
    context = DummyContext.new

    with_fixed_random do
      travel_to @fixed_time do
        context.send(:stream_llm_response) do |stream_proc|
          stream_proc.call("普通の回答です。")
        end
      end
    end

    # Only 3 data chunks, no options event
    assert_equal 3, context.stream.writes.size
    context.stream.writes.each do |write|
      assert_match(/\Adata: /, write)
    end
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
