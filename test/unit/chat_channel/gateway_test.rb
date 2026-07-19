# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelGatewayTest < ActiveSupport::TestCase
  # Records handled messages together with the thread that handled them.
  class RecordingHandler
    attr_reader :handled

    def initialize
      @handled = []
    end

    def handle(message)
      @handled << [ message, Thread.current ]
    end
  end

  # In-memory adapter that dispatches a fixed list of messages when started.
  class FakeGatewayAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :stopped
    attr_accessor :messages_to_dispatch, :after_dispatch

    class << self
      def channel_type
        "gateway_chat"
      end
    end

    def initialize
      super
      @stopped = false
      @messages_to_dispatch = []
    end

    def enabled?
      true
    end

    def start
      @messages_to_dispatch.each { |message| dispatch(message) }
      @after_dispatch&.call
    end

    def stop
      @stopped = true
    end

    def send_message(channel_id:, thread_key:, text:); end

    def resolve_user_email(external_user_id:); end

    def notify_processing(message:); end
  end

  def incoming(text)
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "gateway_chat", channel_id: "C1", thread_key: "C1:1.000001",
      text: text, external_user_id: "U1", dm: false
    )
  end

  setup do
    @gateway = RedmineAiHelper::ChatChannel::Gateway.new
  end

  context "run" do
    should "raise ConfigurationError when no adapter is enabled" do
      @gateway.stubs(:build_enabled_adapters).returns([])

      assert_raises(RedmineAiHelper::ChatChannel::Gateway::ConfigurationError) { @gateway.run }
    end

    should "start enabled adapters and process dispatched messages serially" do
      adapter = FakeGatewayAdapter.new
      handler = RecordingHandler.new
      adapter.instance_variable_set(:@handler, handler)
      messages = [ incoming("one"), incoming("two"), incoming("three") ]
      adapter.messages_to_dispatch = messages
      adapter.after_dispatch = -> { @gateway.shutdown }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      @gateway.run

      assert_equal messages, handler.handled.map(&:first)
      worker_threads = handler.handled.map(&:last).uniq
      assert_equal 1, worker_threads.size, "all messages must be handled by the single worker thread"
    end

    should "wrap each handled message in a connection pool checkout" do
      adapter = FakeGatewayAdapter.new
      adapter.instance_variable_set(:@handler, RecordingHandler.new)
      adapter.messages_to_dispatch = [ incoming("one"), incoming("two") ]
      adapter.after_dispatch = -> { @gateway.shutdown }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])
      ActiveRecord::Base.connection_pool.expects(:with_connection).twice.yields

      @gateway.run
    end

    should "stop all adapters and drain the queue on shutdown" do
      adapter = FakeGatewayAdapter.new
      handler = RecordingHandler.new
      adapter.instance_variable_set(:@handler, handler)
      adapter.messages_to_dispatch = [ incoming("one"), incoming("two") ]
      adapter.after_dispatch = -> { @gateway.shutdown }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      @gateway.run

      assert adapter.stopped, "shutdown must call stop on every adapter"
      assert_equal 2, handler.handled.size, "queued messages must be drained before exiting"
    end

    should "re-raise a non-config adapter crash after shutdown" do
      adapter = FakeGatewayAdapter.new
      adapter.after_dispatch = -> { raise RuntimeError, "adapter blew up" }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      error = assert_raises(RuntimeError) { @gateway.run }
      assert_match(/adapter blew up/, error.message)
      assert adapter.stopped, "shutdown must still be called on the crashed adapter"
    end

    should "raise ConfigurationError when the adapter reports a config error" do
      adapter = FakeGatewayAdapter.new
      adapter.define_singleton_method(:fatal_config_error?) { |_e| true }
      adapter.after_dispatch = -> { raise RuntimeError, "invalid_auth" }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      error = assert_raises(RedmineAiHelper::ChatChannel::Gateway::ConfigurationError) { @gateway.run }
      assert_match(/invalid_auth/, error.message)
    end

    should "keep the worker loop alive when a single message raises" do
      adapter = FakeGatewayAdapter.new
      failing_handler = Class.new do
        def initialize
          @calls = 0
        end

        attr_reader :calls

        def handle(_message)
          @calls += 1
          raise "bad message" if @calls == 1
        end
      end.new
      adapter.instance_variable_set(:@handler, failing_handler)
      adapter.messages_to_dispatch = [ incoming("boom"), incoming("ok") ]
      adapter.after_dispatch = -> { @gateway.shutdown }
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      assert_nothing_raised { @gateway.run }

      assert_equal 2, failing_handler.calls, "worker must continue after a failed message"
    end
  end

  # Adapter that is registered but not enabled.
  class DisabledGatewayAdapter < FakeGatewayAdapter
    class << self
      def channel_type
        "disabled_gateway_chat"
      end
    end

    def enabled?
      false
    end
  end

  context "build_enabled_adapters" do
    should "instantiate only enabled adapters from the registry" do
      RedmineAiHelper::ChatChannel::BaseAdapter.stubs(:adapters).returns(
        { "gateway_chat" => FakeGatewayAdapter, "disabled_gateway_chat" => DisabledGatewayAdapter }
      )

      adapters = @gateway.send(:build_enabled_adapters)

      assert_equal 1, adapters.size
      assert_kind_of FakeGatewayAdapter, adapters.first
    end
  end

  context "dispatch without a gateway" do
    should "fall back to calling the handler directly" do
      adapter = FakeGatewayAdapter.new
      handler = RecordingHandler.new
      adapter.instance_variable_set(:@handler, handler)
      message = incoming("direct")

      adapter.dispatch(message)

      assert_equal [ message ], handler.handled.map(&:first)
    end
  end
end
