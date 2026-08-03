# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelBaseAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  # In-memory adapter used to verify that subclassing BaseAdapter alone is
  # enough to plug a new chat tool into the abstraction layer (SC-006).
  class FakeAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    attr_reader :sent_messages

    class << self
      def channel_type
        "fake_chat"
      end

      def required_setting_fields
        [ :bot_token ]
      end
    end

    def initialize
      super
      @sent_messages = []
    end

    def start
      # No external connection for the in-memory adapter.
    end

    # #stop is not implemented: the shared one in BaseAdapter closes nothing
    # when the adapter never opened a socket (INV-8).

    def send_message(channel_id:, thread_key:, text:)
      @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
    end
  end

  # Adapter that uses the shared WebSocket transport of BaseAdapter. It never
  # opens a real socket: the tests drive the protected transport methods
  # directly with a fake client and fake frames, the same way the Slack
  # adapter's own transport tests do.
  class FakeSocketAdapter < RedmineAiHelper::ChatChannel::BaseAdapter
    # Text frames received through handle_text_frame, as [client, data] pairs.
    # @return [Array<Array>]
    attr_reader :text_frames

    # The value of @last_received_at observed at the moment the text frame was
    # delivered, used to prove the receive time is recorded before dispatch.
    # @return [Float, nil]
    attr_reader :received_at_on_text

    class << self
      def channel_type
        "fake_socket"
      end
    end

    def initialize
      super
      @text_frames = []
    end

    def start
      # No external connection for the in-memory adapter.
    end

    def send_message(channel_id:, thread_key:, text:)
      # Not used by the transport tests.
    end

    protected

    def handle_text_frame(client, data)
      @received_at_on_text = @last_received_at
      @text_frames << [ client, data ]
    end
  end

  # A stand-in for the WebSocket::Client::Simple::Client the handler block
  # receives, so tests never need a real socket. Records every frame sent
  # through it.
  class FakeClient
    Sent = Struct.new(:data, :type)

    attr_reader :sent

    def initialize
      @sent = []
    end

    def send(data, type: :text)
      @sent << Sent.new(data, type)
    end
  end

  # Detects whether two threads ever ran #send concurrently. Only safe as a
  # plain (unlocked) instance variable *because* that is exactly the property
  # under test: if send_frame's @send_mutex serializes calls correctly, this
  # method's body never actually runs on two threads at once.
  #
  # Detection is best effort: it can only observe an overlap the scheduler
  # actually produces. The window is widened deliberately (repeated Thread.pass
  # plus a sleep, both of which release the GVL) so an unserialized caller has
  # many chances to enter. The structural guarantee is asserted separately by
  # the test that expects @send_mutex#synchronize to be held.
  class ConcurrencyDetectingClient
    # How long #send stays inside its critical section. Long enough that a
    # thread waiting on the GVL is scheduled into it if nothing excludes it.
    BUSY_SECONDS = 0.005

    attr_reader :overlap_detected, :calls

    def initialize
      @busy = false
      @overlap_detected = false
      @calls = []
    end

    def send(data, type: :text) # rubocop:disable Lint/UnusedMethodArgument
      @overlap_detected ||= @busy
      @busy = true
      @calls << data
      5.times { Thread.pass }
      sleep BUSY_SECONDS
      # A cleared flag means another call ran to completion inside this one,
      # which catches an overlap the check on entry could still have missed.
      @overlap_detected ||= !@busy
      @busy = false
    end
  end

  # Doubles for the frames handle_frame receives (#type / #data / #code).
  FrameStruct = Struct.new(:type, :data, :code)

  context "automatic registration" do
    should "register subclasses by channel_type" do
      assert_equal FakeAdapter, RedmineAiHelper::ChatChannel::BaseAdapter.adapters["fake_chat"]
    end
  end

  context "settings" do
    should "return the AiHelperChatAdapterSetting for the adapter's channel_type" do
      setting = create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat")

      assert_equal setting, FakeAdapter.new.settings
    end
  end

  context "enabled?" do
    should "be false when no setting exists" do
      assert_not FakeAdapter.new.enabled?
    end

    should "be false when the setting is enabled but a required field is missing" do
      setting = create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", bot_token: nil)
      # Bypass validation to simulate a row saved before the adapter declared
      # the field as required.
      setting.update_column(:enabled, true)

      assert_not FakeAdapter.new.enabled?
    end

    should "be true when enabled and all required fields are present" do
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", enabled: true, bot_token: "xoxb-token", redmine_user_id: 2, default_project_id: 1)

      assert_predicate FakeAdapter.new, :enabled?
    end
  end

  context "handler" do
    should "provide a MessageHandler bound to the adapter" do
      adapter = FakeAdapter.new

      assert_kind_of RedmineAiHelper::ChatChannel::MessageHandler, adapter.handler
    end
  end

  # SC-006: a brand-new tool integration must work end to end with nothing
  # but a BaseAdapter subclass — no changes to MessageHandler, the models or
  # the Slack adapter.
  context "end-to-end with a fictional adapter" do
    should "accept a question and return the answer through the shared core" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      adapter = FakeAdapter.new
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "fake_chat", channel_id: "FC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "fictional answer")
      )

      adapter.dispatch(RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "FC1", thread_key: "FC1:1.000001",
        text: "hello from a fictional tool", dm: false
      ))

      assert_equal [ { channel_id: "FC1", thread_key: "FC1:1.000001", text: "fictional answer" } ],
                   adapter.sent_messages
      conversation = AiHelperConversation.first
      assert_equal user, conversation.user
      assert_equal "fake_chat", conversation.channel_conversation.channel_type
    end
  end

  context "history support" do
    should "not support history by default" do
      assert_not_predicate FakeAdapter.new, :supports_history?
    end

    should "raise NotImplementedError from fetch_thread_history" do
      error = assert_raises(NotImplementedError) do
        FakeAdapter.new.fetch_thread_history(channel_id: "FC1", thread_key: "FC1:1.000001")
      end

      assert_match(/fetch_thread_history/, error.message)
    end

    should "raise NotImplementedError from fetch_channel_history" do
      error = assert_raises(NotImplementedError) do
        FakeAdapter.new.fetch_channel_history(
          channel_id: "FC1", before: "1.000002", since: 48.hours.ago, limit: 20
        )
      end

      assert_match(/fetch_channel_history/, error.message)
    end
  end

  # SC-006: an adapter that does not implement history retrieval keeps working
  # through the unchanged core; the only difference is that no prior context is
  # available to the answer.
  context "end-to-end with an adapter that does not support history" do
    should "answer without fetching or storing any context" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      adapter = FakeAdapter.new
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_chat", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "fake_chat", channel_id: "FC2", project: project)
      adapter.expects(:fetch_thread_history).never
      adapter.expects(:fetch_channel_history).never
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "answer without context")
      )

      adapter.dispatch(RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "FC2", thread_key: "FC2:1.000001",
        message_ts: "1.000001", text: "hello", dm: false
      ))

      assert_equal "answer without context", adapter.sent_messages.first[:text]
      conversation = AiHelperConversation.first
      assert_equal %w[user assistant], conversation.messages.order(:id).pluck(:role)
      assert_nil conversation.channel_conversation.last_imported_message_key
    end
  end

  context "IncomingMessage" do
    should "hold the normalized fields" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat",
        channel_id: "C123",
        thread_key: "C123:1700000000.000100",
        message_ts: "1700000000.000200",
        text: "hello",
        dm: true
      )

      assert_equal "fake_chat", message.channel_type
      assert_equal "C123", message.channel_id
      assert_equal "C123:1700000000.000100", message.thread_key
      assert_equal "1700000000.000200", message.message_ts
      assert_equal "hello", message.text
      assert message.dm?
    end

    should "not be in a thread unless the adapter says so" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "C123", thread_key: "C123:1.000100", text: "hello"
      )

      assert_not_predicate message, :in_thread?
    end

    should "carry the in_thread flag set by the adapter" do
      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "fake_chat", channel_id: "C123", thread_key: "C123:1.000100",
        text: "hello", in_thread: true
      )

      assert_predicate message, :in_thread?
    end
  end

  context "issue link format" do
    should "V-18: return PLAIN format when the adapter does not declare one" do
      adapter = FakeAdapter.new

      assert_equal RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN,
                   adapter.issue_link_format
    end

    should "V-20: have render results that match the format's pattern for PLAIN" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::PLAIN
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end

    should "V-20: have render results that match the format's pattern for SLACK" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end

    should "V-20: have render results that match the format's pattern for DISCORD" do
      format = RedmineAiHelper::ChatChannel::IssueLinkFormatter::DISCORD
      rendered = format.render("#1549", "https://r.example.com/issues/1549")

      assert format.pattern.match?(rendered)
    end
  end

  # C-1: the shared frame dispatcher. Every adapter that speaks WebSocket
  # routes its ws.on(:message) block through this method.
  context "shared transport: handle_frame" do
    setup do
      @adapter = FakeSocketAdapter.new
    end

    should "C-1.1: update last_received_at to the current monotonic time before dispatching by type" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12345.0)
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:unknown, nil, nil))

      assert_equal 12345.0, @adapter.instance_variable_get(:@last_received_at)
    end

    should "C-1.1: record the receive time before the subclass sees the frame" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12345.0)

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:text, "payload", nil))

      assert_equal 12345.0, @adapter.received_at_on_text
    end

    should "C-1.2: echo a ping's payload back as a pong to the frame's own client" do
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "Ping from applink-2", nil))

      assert_equal [ FakeClient::Sent.new("Ping from applink-2", :pong) ], client.sent
    end

    should "C-1.3: delegate a text frame to handle_text_frame with the frame's own client" do
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:text, "payload", nil))

      assert_equal [ [ client, "payload" ] ], @adapter.text_frames
    end

    should "C-1.4: delegate a close frame to handle_close_frame with the close code" do
      @adapter.expects(:handle_close_frame).with(1001)

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:close, nil, 1001))
    end

    should "C-1.5: do nothing but record the receive time for an unknown frame type" do
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:pong, nil, nil))

      assert_empty client.sent
      assert_empty @adapter.text_frames
    end

    should "C-1.6: log and notify connection_ended instead of letting an exception escape to the gem" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      client = FakeClient.new
      client.stubs(:send).raises(IOError, "not opened for writing")
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/fake_socket: error while handling frame.*not opened for writing/m))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised do
        @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "payload", nil))
      end
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-1.9: carry a fatal credential error over to the connecting thread instead of reconnecting" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      error = StandardError.new("invalid_auth")
      client = FakeClient.new
      client.stubs(:send).raises(error)
      @adapter.stubs(:fatal_config_error?).returns(true)
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/fake_socket: error while handling frame.*invalid_auth/m))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised do
        @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "payload", nil))
      end

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
      raised = assert_raises(StandardError) { @adapter.send(:raise_fatal_error!) }
      assert_same error, raised
    end

    should "C-1.9: only end the connection when the error is not a fatal one" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      client = FakeClient.new
      client.stubs(:send).raises(IOError, "not opened for writing")
      @adapter.stubs(:ai_helper_logger).returns(stub_everything("logger"))

      @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "payload", nil))

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
      assert_nothing_raised { @adapter.send(:raise_fatal_error!) }
    end

    should "C-1.7: answer a ping and deliver a text frame while @ws is still nil (pre-handshake window)" do
      assert_nil @adapter.instance_variable_get(:@ws)
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "payload", nil))
      @adapter.send(:handle_frame, client, FrameStruct.new(:text, "envelope", nil))

      assert_nil @adapter.instance_variable_get(:@ws)
      assert_equal [ FakeClient::Sent.new("payload", :pong) ], client.sent
      assert_equal [ [ client, "envelope" ] ], @adapter.text_frames
    end

    should "C-1.8: log the close code and notify connection_ended by default" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:info).with("fake_socket: close frame received (code 1000)")
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:handle_close_frame, 1000)

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-1.8: log 'none' instead of a blank code for a close frame without a status code" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:info).with("fake_socket: close frame received (code none)")
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:handle_close_frame, nil)
    end

    should "require a subclass to implement handle_text_frame" do
      error = assert_raises(NotImplementedError) do
        FakeAdapter.new.send(:handle_text_frame, nil, "payload")
      end

      assert_match(/handle_text_frame/, error.message)
    end
  end

  # C-2: the shared monitor loop. Liveness is judged only by whether frames
  # arrive; the loop never probes the connection itself.
  context "shared transport: watchdog_loop" do
    setup do
      @adapter = FakeSocketAdapter.new
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
    end

    should "C-2.2: request a reconnect and leave the loop once the receive timeout has elapsed" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(131.0)

      @adapter.send(:watchdog_loop)

      assert @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "C-2.3: warn with the actual elapsed seconds and without any credential" do
      create(:ai_helper_chat_adapter_setting, channel_type: "fake_socket", bot_token: "socket-secret")
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(131.0)
      warnings = []
      logger = mock("logger")
      logger.stubs(:warn).with { |message| warnings << message; true }
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:watchdog_loop)

      assert_equal [ "fake_socket: no frame received for 31.0s, reconnecting" ], warnings
      assert_no_match(/socket-secret/, warnings.first)
    end

    should "C-2.4: exit immediately when the connection has already ended, without waiting for the timeout" do
      @adapter.instance_variable_set(:@last_received_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
      queue = Queue.new
      queue.push(true)
      @adapter.instance_variable_set(:@connection_ended, queue)

      @adapter.send(:watchdog_loop)

      assert_not @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "C-2.5: exit immediately without polling the queue when already stopped" do
      @adapter.instance_variable_set(:@stopped, true)
      FakeSocketAdapter.expects(:timed_queue_pop).never

      @adapter.send(:watchdog_loop)
    end

    should "C-2.5: exit immediately without polling the queue when a reconnect was already requested" do
      @adapter.instance_variable_set(:@reconnect_requested, true)
      FakeSocketAdapter.expects(:timed_queue_pop).never

      @adapter.send(:watchdog_loop)
    end

    should "C-2.6: wait the shorter of the receive deadline and the next scheduled action" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(110.0)
      @adapter.stubs(:next_scheduled_action_in).returns(5.0)
      waits = []
      FakeSocketAdapter.stubs(:timed_queue_pop).with { |_queue, wait| waits << wait; true }.returns(true)

      @adapter.send(:watchdog_loop)

      assert_equal [ 5.0 ], waits
    end

    should "C-2.7: wait only for the receive deadline when no action is scheduled" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(110.0)
      waits = []
      FakeSocketAdapter.stubs(:timed_queue_pop).with { |_queue, wait| waits << wait; true }.returns(true)

      @adapter.send(:watchdog_loop)

      assert_equal [ 20.0 ], waits
    end

    should "C-2.8: perform the scheduled action when the wait ends without an end notification" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(110.0)
      FakeSocketAdapter.stubs(:timed_queue_pop).returns(nil, true)
      @adapter.expects(:perform_scheduled_action).once

      @adapter.send(:watchdog_loop)
    end

    should "C-2.9: evaluate the receive timeout on every pass so a shortened bound takes effect" do
      @adapter.instance_variable_set(:@last_received_at, 90.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(100.0)
      @adapter.stubs(:receive_timeout_seconds).returns(30, 5)
      waits = []
      FakeSocketAdapter.stubs(:timed_queue_pop).with { |_queue, wait| waits << wait; true }.returns(nil)

      @adapter.send(:watchdog_loop)

      assert_equal [ 20.0 ], waits,
                   "only the first pass may wait: the second must see the shortened bound as already elapsed"
      assert @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "C-2.10: recompute the remaining wait when a frame arrives right at the deadline" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(100.0, 120.0)
      @adapter.instance_variable_set(:@last_received_at, 90.0)
      waits = []
      FakeSocketAdapter.stubs(:timed_queue_pop).with do |_queue, wait|
        waits << wait
        @adapter.instance_variable_set(:@last_received_at, 115.0) if waits.size == 1
        true
      end.returns(nil, true)

      @adapter.send(:watchdog_loop)

      assert_equal [ 20.0, 25.0 ], waits
    end

    should "use the default receive timeout of 30 seconds" do
      assert_equal 30, RedmineAiHelper::ChatChannel::BaseAdapter::DEFAULT_RECEIVE_TIMEOUT_SECONDS
      assert_equal 30, @adapter.send(:receive_timeout_seconds)
    end

    should "schedule no action and do nothing by default" do
      assert_nil @adapter.send(:next_scheduled_action_in)
      assert_nothing_raised { @adapter.send(:perform_scheduled_action) }
    end
  end

  # C-3: every write to the socket - payloads, pongs and the close frame -
  # goes through the adapter's single mutex.
  context "shared transport: send_frame and close_socket" do
    setup do
      @adapter = FakeSocketAdapter.new
    end

    should "C-3.1: never let two threads send through the client at the same time" do
      client = ConcurrencyDetectingClient.new

      threads = 5.times.map { |i| Thread.new { @adapter.send(:send_frame, client, "msg#{i}") } }
      threads.each(&:join)

      assert_not client.overlap_detected
      assert_equal 5, client.calls.size
    end

    should "C-3.1: hold send_mutex while sending through the client" do
      client = FakeClient.new
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      @adapter.send(:send_frame, client, "hello", type: :pong)

      assert_equal [ FakeClient::Sent.new("hello", :pong) ], client.sent
    end

    should "C-3.5: do nothing and raise no exception when the client is nil" do
      # The mutex must still be taken: a nil check that returns early would
      # move the guard out of the serialized path for every other caller too.
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      assert_nothing_raised do
        @adapter.send(:send_frame, nil, "hello")
      end
    end

    should "C-3.9: send a text frame when no frame type is given" do
      client = FakeClient.new

      @adapter.send(:send_frame, client, "hello")

      assert_equal [ FakeClient::Sent.new("hello", :text) ], client.sent
    end

    should "C-3.6: own exactly one mutex that survives every send and close" do
      mutex = @adapter.instance_variable_get(:@send_mutex)
      assert_kind_of Mutex, mutex

      @adapter.send(:send_frame, FakeClient.new, "hello")
      @adapter.send(:close_socket)

      assert_same mutex, @adapter.instance_variable_get(:@send_mutex)
    end

    should "C-3.4: close the socket while holding send_mutex" do
      ws = mock("ws")
      ws.expects(:close)
      @adapter.instance_variable_set(:@ws, ws)
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      @adapter.send(:close_socket)

      assert_nil @adapter.instance_variable_get(:@ws)
    end

    should "C-3.7: swallow IOError raised while closing" do
      ws = mock("ws")
      ws.expects(:close).raises(IOError, "closed stream")
      @adapter.instance_variable_set(:@ws, ws)
      logger = mock("logger")
      logger.expects(:debug).with(regexp_matches(/fake_socket: error while closing socket: closed stream/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end

    should "C-3.7: swallow SystemCallError raised while closing" do
      ws = mock("ws")
      ws.expects(:close).raises(Errno::ECONNRESET)
      @adapter.instance_variable_set(:@ws, ws)
      logger = mock("logger")
      logger.expects(:debug).with(regexp_matches(/fake_socket: error while closing socket: .*Connection reset/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end

    should "C-3.8: do nothing when there is no socket to close" do
      assert_nil @adapter.instance_variable_get(:@ws)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end
  end

  # C-4 and C-5: ending a connection, and the retry pacing #start uses.
  context "shared transport: connection end, stop flag and backoff" do
    setup do
      @adapter = FakeSocketAdapter.new
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
    end

    should "C-4.1: flag the reconnect and notify connection_ended on request_reconnect" do
      @adapter.send(:request_reconnect)

      assert @adapter.instance_variable_get(:@reconnect_requested)
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-4.2: notify connection_ended on connection_ended!" do
      @adapter.send(:connection_ended!)

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-4.3: log the error and notify connection_ended on socket_errored" do
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/fake_socket: websocket error.*boom/m))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:socket_errored, StandardError.new("boom"))

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-4.4: raise nothing when there is no connection to notify" do
      adapter = FakeSocketAdapter.new

      assert_nothing_raised do
        adapter.send(:request_reconnect)
        adapter.send(:connection_ended!)
        adapter.send(:socket_errored, StandardError.new("boom"))
      end
    end

    should "C-5.1: report stopped? from the stop flag" do
      assert_not @adapter.send(:stopped?)

      @adapter.instance_variable_set(:@stopped, true)

      assert @adapter.send(:stopped?)
    end

    should "C-5.2: back off exponentially from 1 up to 60 seconds" do
      assert_equal 60, RedmineAiHelper::ChatChannel::BaseAdapter::MAX_BACKOFF_SECONDS
      assert_equal([ 1, 2, 4, 8, 16, 32, 60, 60 ], (1..8).map { @adapter.send(:next_backoff) })
    end

    should "C-5.3: reset the backoff after a successful connection" do
      3.times { @adapter.send(:next_backoff) }
      @adapter.send(:reset_backoff)

      assert_equal 1, @adapter.send(:next_backoff)
    end

    should "C-5.4: start out not stopped, with a backoff of 1 and no recorded frame" do
      adapter = FakeSocketAdapter.new

      assert_not adapter.send(:stopped?)
      assert_equal 1, adapter.send(:next_backoff)
      assert_equal 0.0, adapter.instance_variable_get(:@last_received_at)
    end

    should "C-5.5: raise the stop flag, wake the monitor loop and close the socket on stop" do
      ws = mock("ws")
      ws.expects(:close)
      @adapter.instance_variable_set(:@ws, ws)

      @adapter.stop

      assert @adapter.send(:stopped?)
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
      assert_nil @adapter.instance_variable_get(:@ws)
    end

    should "C-5.5: stop an adapter that never opened a socket without raising" do
      adapter = FakeSocketAdapter.new

      assert_nothing_raised { adapter.stop }
      assert adapter.send(:stopped?)
    end

    should "C-5.1: clear the stop flag when the adapter is started again" do
      @adapter.instance_variable_set(:@stopped, true)

      @adapter.send(:clear_stop_flag)

      assert_not @adapter.send(:stopped?)
    end
  end
end
