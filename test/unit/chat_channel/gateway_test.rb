# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelGatewayTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

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

    # FR-010 / SC-006: adding the (abstract) InboundAdapter base class must
    # not change how the gateway enumerates and starts existing adapters.
    should "build from the real registry without error, and never include the abstract InboundAdapter itself" do
      adapters = @gateway.send(:build_enabled_adapters)

      assert_kind_of Array, adapters
      assert_not_includes adapters.map(&:class), RedmineAiHelper::ChatChannel::InboundAdapter
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

  # Adapter that records the order of processing-reaction calls.
  class ReactionGatewayAdapter < FakeGatewayAdapter
    attr_reader :events
    attr_accessor :show_error, :clear_error

    def initialize
      super
      @events = []
    end

    def show_processing(message:)
      @events << [ :show, message.text ]
      raise @show_error if @show_error
    end

    def clear_processing(message:)
      @events << [ :clear, message.text ]
      raise @clear_error if @clear_error
    end
  end

  # Handler that records ordering against the adapter's events.
  class OrderedHandler
    def initialize(adapter, fail_on: nil)
      @adapter = adapter
      @fail_on = fail_on
    end

    def handle(message)
      @adapter.events << [ :handle, message.text ]
      raise "handler failed" if message.text == @fail_on
    end
  end

  context "processing reaction" do
    setup do
      @adapter = ReactionGatewayAdapter.new
      @adapter.instance_variable_set(:@handler, OrderedHandler.new(@adapter))
      @gateway.stubs(:build_enabled_adapters).returns([ @adapter ])
    end

    should "show processing before the message is queued" do
      queue = @gateway.instance_variable_get(:@queue)
      @adapter.expects(:show_processing).with { |args| queue.empty? && args[:message].text == "one" }

      @gateway.enqueue(@adapter, incoming("one"))

      assert_equal 1, queue.size
    end

    should "not show processing for a message dropped after shutdown" do
      @adapter.after_dispatch = -> do
        @gateway.shutdown
        @gateway.enqueue(@adapter, incoming("late"))
      end
      @adapter.messages_to_dispatch = [ incoming("one") ]

      @gateway.run

      assert_equal [ [ :show, "one" ], [ :handle, "one" ], [ :clear, "one" ] ], @adapter.events
    end

    should "clear the mark and not queue when shutdown is requested while showing processing" do
      queue = @gateway.instance_variable_get(:@queue)
      @adapter.stubs(:show_processing).with { @gateway.shutdown; true }
      @adapter.expects(:clear_processing).with { |args| args[:message].text == "late" }

      @gateway.enqueue(@adapter, incoming("late"))

      assert_equal [ RedmineAiHelper::ChatChannel::Gateway::SHUTDOWN ], Array.new(queue.size) { queue.pop }
    end

    should "clear processing after a successful handle" do
      @adapter.messages_to_dispatch = [ incoming("one") ]
      @adapter.after_dispatch = -> { @gateway.shutdown }

      @gateway.run

      assert_equal [ [ :show, "one" ], [ :handle, "one" ], [ :clear, "one" ] ], @adapter.events
    end

    should "clear processing even when handle raises" do
      @adapter.instance_variable_set(:@handler, OrderedHandler.new(@adapter, fail_on: "boom"))
      @adapter.messages_to_dispatch = [ incoming("boom") ]
      @adapter.after_dispatch = -> { @gateway.shutdown }

      @gateway.run

      assert_equal(1, @adapter.events.count { |kind, _| kind == :clear })
    end

    should "pair every show with a clear and drain everything queued before shutdown" do
      @adapter.messages_to_dispatch = [ incoming("a"), incoming("b"), incoming("c") ]
      @adapter.after_dispatch = -> { @gateway.shutdown }

      @gateway.run

      assert_equal(3, @adapter.events.count { |kind, _| kind == :show })
      assert_equal(3, @adapter.events.count { |kind, _| kind == :handle })
      assert_equal(3, @adapter.events.count { |kind, _| kind == :clear })
    end

    should "still queue and process the message when show_processing raises, and log it" do
      @adapter.show_error = RuntimeError.new("missing_scope")
      @adapter.messages_to_dispatch = [ incoming("one") ]
      @adapter.after_dispatch = -> { @gateway.shutdown }
      logger = stub_everything("logger")
      logger.expects(:error).with { |m| m.include?("gateway_chat") && m.include?("C1:1.000001") && m.include?("missing_scope") }
      @gateway.stubs(:ai_helper_logger).returns(logger)

      @gateway.run

      assert_includes @adapter.events, [ :handle, "one" ]
    end

    should "continue to the next message when clear_processing raises, and log it" do
      @adapter.clear_error = RuntimeError.new("message_not_found")
      @adapter.messages_to_dispatch = [ incoming("one"), incoming("two") ]
      @adapter.after_dispatch = -> { @gateway.shutdown }
      logger = stub_everything("logger")
      logger.expects(:error).twice.with { |m| m.include?("gateway_chat") && m.include?("C1:1.000001") && m.include?("message_not_found") }
      @gateway.stubs(:ai_helper_logger).returns(logger)

      @gateway.run

      assert_equal(2, @adapter.events.count { |kind, _| kind == :handle })
    end

    should "not log an error for expected states (already reacted, no reaction)" do
      slack = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter
      AiHelperChatAdapterSetting.delete_all
      create(:ai_helper_chat_adapter_setting, channel_type: "slack", enabled: true,
                        app_token: "xapp-secret", bot_token: "xoxb-secret", redmine_user_id: 2, default_project_id: 1)
      adapter = slack.new
      adapter.stubs(:api_call).raises(slack::SlackApiError.new("x", code: "already_reacted"))
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "slack", channel_id: "C1", thread_key: "C1:1.0", message_ts: "1.0", text: "hi"
      )
      @gateway.expects(:ai_helper_logger).never

      @gateway.enqueue(adapter, message)
      adapter.unstub(:api_call)
      adapter.stubs(:api_call).raises(slack::SlackApiError.new("x", code: "no_reaction"))
      @gateway.send(:clear_processing_safely, adapter, message)
    end

    should "send the real Slack and Discord reaction requests from enqueue" do
      AiHelperChatAdapterSetting.delete_all
      create(:ai_helper_chat_adapter_setting, channel_type: "slack", enabled: true,
                        app_token: "xapp-secret", bot_token: "xoxb-secret", redmine_user_id: 2, default_project_id: 1)
      create(:ai_helper_chat_adapter_setting, channel_type: "discord", enabled: true,
                        bot_token: "discord-secret", redmine_user_id: 2, default_project_id: 1)
      sent = []
      Net::HTTP.any_instance.stubs(:request).with { |req| sent << req; true }
               .returns(stub(body: { "ok" => true }.to_json, code: "200"))
      slack_message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "slack", channel_id: "C9", thread_key: "C9:1.0", message_ts: "5.5", text: "hi"
      )
      discord_message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "discord", channel_id: "P1", thread_key: "P1:T1", message_ts: "M7", text: "hi",
        origin_channel_id: "T1"
      )

      @gateway.enqueue(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.new, slack_message)
      @gateway.enqueue(RedmineAiHelper::ChatChannel::Adapters::DiscordAdapter.new, discord_message)

      assert_equal "/api/reactions.add", sent[0].path
      assert_equal({ "channel" => "C9", "timestamp" => "5.5", "name" => "hourglass_flowing_sand" },
                   URI.decode_www_form(sent[0].body).to_h)
      assert_equal "/api/v10/channels/T1/messages/M7/reactions/%E2%8F%B3/@me", sent[1].path
    end

    should "not include the bot token in logged reaction errors" do
      slack = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter
      AiHelperChatAdapterSetting.delete_all
      create(:ai_helper_chat_adapter_setting, channel_type: "slack", enabled: true,
                        app_token: "xapp-secret", bot_token: "xoxb-secret", redmine_user_id: 2, default_project_id: 1)
      adapter = slack.new
      Net::HTTP.any_instance.stubs(:request).returns(stub(body: { "ok" => false, "error" => "missing_scope" }.to_json))
      logged = []
      logger = stub_everything("logger")
      logger.stubs(:error).with { |m| logged << m; true }
      @gateway.stubs(:ai_helper_logger).returns(logger)
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "slack", channel_id: "C1", thread_key: "C1:1.0", message_ts: "1.0", text: "hi"
      )

      @gateway.enqueue(adapter, message)

      assert_equal 1, logged.size
      assert_no_match(/xoxb-secret/, logged.first)
    end

    should "not queue or react after shutdown but drain earlier messages with matching clears" do
      @adapter.messages_to_dispatch = [ incoming("a"), incoming("b") ]
      @adapter.after_dispatch = -> do
        @gateway.shutdown
        @gateway.enqueue(@adapter, incoming("late"))
      end

      @gateway.run

      assert_equal(2, @adapter.events.count { |kind, _| kind == :clear })
      assert_empty(@adapter.events.select { |_, text| text == "late" })
    end
  end
end
