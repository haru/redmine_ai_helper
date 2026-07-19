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

    def notify_processing(message:); end
  end

  def incoming(text)
    RedmineAiHelper::ChatChannel::IncomingMessage.new(
      channel_type: "gateway_chat", channel_id: "C1", thread_key: "C1:1.000001",
      text: text, dm: false
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

    should "silently drop messages enqueued after shutdown" do
      adapter = FakeGatewayAdapter.new
      handler = RecordingHandler.new
      adapter.instance_variable_set(:@handler, handler)
      adapter.messages_to_dispatch = [ incoming("one") ]
      adapter.after_dispatch = -> do
        @gateway.shutdown
        @gateway.enqueue(adapter, incoming("late"))
      end
      @gateway.stubs(:build_enabled_adapters).returns([ adapter ])

      @gateway.run

      assert_equal 1, handler.handled.size, "late message must be dropped after shutdown"
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

  # In-memory adapter that raises a configuration error the moment it starts.
  class ConfigErrorAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    class << self
      def channel_type
        "us4_config_error"
      end
    end

    def enabled?
      true
    end

    def fatal_config_error?(_error)
      true
    end

    def start
      raise "invalid_auth"
    end

    def stop; end
    def send_message(channel_id:, thread_key:, text:); end
    def notify_processing(message:); end
  end

  # In-memory adapter that raises a non-configuration error when it starts.
  class RuntimeErrorAdapter < ConfigErrorAdapter
    class << self
      def channel_type
        "us4_runtime_error"
      end
    end

    def fatal_config_error?(_error)
      false
    end

    def start
      raise "boom"
    end
  end

  # In-memory adapter that blocks until stopped, optionally running a callback
  # (e.g. dispatching a message) when it starts.
  class BlockingAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_accessor :on_start

    class << self
      def channel_type
        "us4_blocking"
      end
    end

    def initialize
      super
      @latch = Queue.new
      @started = Queue.new
    end

    def enabled?
      true
    end

    def start
      @on_start&.call(self)
      @started.push(true)
      @latch.pop
    end

    def wait_until_started(timeout)
      self.class.timed_queue_pop(@started, timeout)
    end

    def stop
      @latch.push(true)
    end

    def send_message(channel_id:, thread_key:, text:); end
    def notify_processing(message:); end
  end

  # Handler that signals a queue after handling a message.
  class SignalingHandler
    def initialize(signal_queue)
      @signal_queue = signal_queue
    end

    def handle(_message)
      @signal_queue.push(true)
    end
  end

  context "multi-adapter fault isolation (US4)" do
    should "keep processing on a live adapter after another dies with a config error" do
      handled = Queue.new
      dead = ConfigErrorAdapter.new
      live = BlockingAdapter.new
      live.instance_variable_set(:@handler, SignalingHandler.new(handled))
      live.on_start = ->(adapter) { adapter.dispatch(incoming("hi")) }
      @gateway.stubs(:build_enabled_adapters).returns([ dead, live ])

      gateway_thread = Thread.new { @gateway.run }
      begin
        assert RedmineAiHelper::ChatChannel::BaseAdapter.timed_queue_pop(handled, 5), "the live adapter must keep processing after the other adapter dies"
        @gateway.shutdown
        assert_nothing_raised { gateway_thread.value }
      ensure
        gateway_thread.join(5)
      end
    end

    should "raise ConfigurationError when all adapters die with config errors" do
      @gateway.stubs(:build_enabled_adapters).returns([ ConfigErrorAdapter.new, ConfigErrorAdapter.new ])

      assert_raises(RedmineAiHelper::ChatChannel::Gateway::ConfigurationError) { @gateway.run }
    end

    should "raise the original error when all adapters die with runtime errors" do
      @gateway.stubs(:build_enabled_adapters).returns([ RuntimeErrorAdapter.new, RuntimeErrorAdapter.new ])

      error = assert_raises(RuntimeError) { @gateway.run }
      assert_match(/boom/, error.message)
    end

    should "prefer the runtime error over a configuration error when all adapters die with a mix of both" do
      @gateway.stubs(:build_enabled_adapters).returns([ ConfigErrorAdapter.new, RuntimeErrorAdapter.new ])

      error = assert_raises(RuntimeError) { @gateway.run }
      assert_match(/boom/, error.message)
    end

    should "not raise after a graceful shutdown even if an adapter died earlier" do
      dead = ConfigErrorAdapter.new
      live = BlockingAdapter.new
      @gateway.stubs(:build_enabled_adapters).returns([ dead, live ])

      gateway_thread = Thread.new { @gateway.run }
      begin
        assert live.wait_until_started(5), "the live adapter must start"
        @gateway.shutdown
        assert_nothing_raised { gateway_thread.value }
      ensure
        gateway_thread.join(5)
      end
    end
  end
end
