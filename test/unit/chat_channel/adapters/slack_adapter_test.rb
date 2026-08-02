# frozen_string_literal: true

require File.expand_path("../../../../test_helper", __FILE__)

class ChatChannelSlackAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  setup do
    AiHelperChatAdapterSetting.delete_all
    create(:ai_helper_chat_adapter_setting,
           channel_type: "slack", enabled: true,
           app_token: "xapp-secret", bot_token: "xoxb-secret", redmine_user_id: 2,
           default_project_id: 1)
    @adapter = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.new
  end

  def stub_api_response(body)
    stub(body: body.to_json)
  end

  # Answers the Web API calls with the given bodies in call order and records
  # the requests so their form parameters can be asserted.
  def stub_slack_calls(*bodies)
    @slack_requests = []
    responses = bodies.map { |body| stub_api_response(body) }
    Net::HTTP.any_instance.stubs(:request).with { |request| @slack_requests << request; true }
             .returns(*responses)
  end

  def slack_form(index)
    URI.decode_www_form(@slack_requests[index].body.to_s).to_h
  end

  def slack_paths
    @slack_requests.map(&:path)
  end

  def slack_message(text:, user: "U1", ts: "1.000001", subtype: nil, bot_id: nil,
                    username: nil, bot_profile: nil)
    message = { "type" => "message", "ts" => ts, "text" => text }
    message["user"] = user if user
    message["subtype"] = subtype if subtype
    message["bot_id"] = bot_id if bot_id
    message["username"] = username if username
    message["bot_profile"] = bot_profile if bot_profile
    message
  end

  def user_info(display_name: nil, real_name: nil, name: nil)
    { "ok" => true,
      "user" => { "profile" => { "display_name" => display_name.to_s },
                  "real_name" => real_name.to_s, "name" => name.to_s } }
  end

  def replies_body(messages, next_cursor: nil)
    body = { "ok" => true, "messages" => messages }
    body["response_metadata"] = { "next_cursor" => next_cursor.to_s }
    body
  end

  context "registration and settings" do
    should "declare channel_type slack" do
      assert_equal "slack", RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.channel_type
      assert_equal RedmineAiHelper::ChatChannel::Adapters::SlackAdapter,
                   RedmineAiHelper::ChatChannel::BaseAdapter.adapters["slack"]
    end

    should "require both tokens" do
      assert_equal [ :app_token, :bot_token ],
                   RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.required_setting_fields
    end

    should "be enabled with tokens present" do
      assert_predicate @adapter, :enabled?
    end
  end

  context "web api" do
    should "configure open and read timeouts of 10 seconds" do
      http = @adapter.send(:build_http, URI("https://slack.com/api/auth.test"))

      assert_equal 10, http.open_timeout
      assert_equal 10, http.read_timeout
    end

    should "raise on ok:false responses" do
      Net::HTTP.any_instance.stubs(:request).returns(stub_api_response({ "ok" => false, "error" => "invalid_auth" }))

      error = assert_raises(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError) do
        @adapter.send(:api_call, "auth.test", token: "xoxb-secret")
      end
      assert_match(/invalid_auth/, error.message)
    end

    should "return the parsed body on success" do
      Net::HTTP.any_instance.stubs(:request).returns(stub_api_response({ "ok" => true, "url" => "wss://example" }))

      body = @adapter.send(:api_call, "apps.connections.open", token: "xapp-secret")

      assert_equal "wss://example", body["url"]
    end
  end

  context "connection lifecycle" do
    should "obtain the websocket url with the app token" do
      @adapter.expects(:api_call).with("apps.connections.open", token: "xapp-secret").returns({ "ok" => true, "url" => "wss://example" })

      assert_equal "wss://example", @adapter.send(:open_connection_url)
    end

    should "terminate without retry when apps.connections.open fails" do
      @adapter.stubs(:fetch_bot_user_id).returns("B001")
      @adapter.expects(:open_connection_url).once.raises(
        RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError, "invalid_auth"
      )
      @adapter.expects(:listen).never

      assert_raises(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError) { @adapter.start }
    end

    should "terminate without retry when auth.test fails" do
      @adapter.expects(:fetch_bot_user_id).raises(
        RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError, "invalid_auth"
      )
      @adapter.expects(:open_connection_url).never

      assert_raises(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError) { @adapter.start }
    end

    should "fetch the bot user id via auth.test on start" do
      @adapter.expects(:api_call).with("auth.test", token: "xoxb-secret").returns({ "ok" => true, "user_id" => "B001" })
      @adapter.expects(:open_connection_url).with { @adapter.stop; true }.returns("wss://example")
      @adapter.stubs(:listen)

      @adapter.start

      assert_equal "B001", @adapter.bot_user_id
    end

    should "reconnect with a new url after a disconnect envelope" do
      @adapter.stubs(:fetch_bot_user_id).returns("B001")
      urls = sequence("urls")
      @adapter.expects(:open_connection_url).twice.in_sequence(urls).returns("wss://one", "wss://two")
      listened = []
      @adapter.stubs(:listen).with do |url|
        listened << url
        @adapter.handle_envelope({ "type" => "disconnect", "reason" => "refresh" }.to_json) if listened.size == 1
        @adapter.stop if listened.size == 2
        true
      end

      @adapter.start

      assert_equal [ "wss://one", "wss://two" ], listened
    end

    should "back off exponentially from 1 up to 60 seconds" do
      expected = [ 1, 2, 4, 8, 16, 32, 60, 60 ]

      assert_equal(expected, (1..8).map { @adapter.send(:next_backoff) })
    end

    should "reset the backoff after a successful connection" do
      3.times { @adapter.send(:next_backoff) }
      @adapter.send(:reset_backoff)

      assert_equal 1, @adapter.send(:next_backoff)
    end

    should "log the connection establishment on hello" do
      @adapter.handle_envelope({ "type" => "hello" }.to_json)

      assert_predicate @adapter, :connected?
    end

    should "back off before reconnecting when the connection ends without hello" do
      @adapter.stubs(:fetch_bot_user_id).returns("B001")
      @adapter.stubs(:open_connection_url).returns("wss://example")
      slept = []
      @adapter.stubs(:sleep).with { |seconds| slept << seconds; true }
      call_count = 0
      @adapter.stubs(:listen).with do |_url|
        call_count += 1
        @adapter.stop if call_count == 2
        true
      end

      @adapter.start

      assert_equal 2, call_count, "adapter must retry after a hello-less clean close"
      assert_equal [ 1 ], slept, "a backoff sleep must happen before the retry"
    end
  end

  context "frame handling" do
    should "update last_received_at to the current monotonic time before dispatching by type" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12345.0)
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:unknown, nil, nil))

      assert_equal 12345.0, @adapter.instance_variable_get(:@last_received_at)
      assert_empty client.sent
    end

    should "still pass text frames to handle_envelope as before" do
      @adapter.expects(:handle_envelope).with("payload")

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:text, "payload", nil))
    end

    should "echo a ping's payload back as a pong to the frame's own client" do
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "Ping from applink-2", nil))

      assert_equal [ FakeClient::Sent.new("Ping from applink-2", :pong) ], client.sent
    end

    should "answer a ping even while @ws is still nil (pre-handshake window)" do
      assert_nil @adapter.instance_variable_get(:@ws)
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "Ping from applink-2", nil))

      assert_nil @adapter.instance_variable_get(:@ws)
      assert_equal [ FakeClient::Sent.new("Ping from applink-2", :pong) ], client.sent
    end

    should "treat an incoming pong frame as a no-op besides updating last_received_at" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(12345.0)
      client = FakeClient.new

      @adapter.send(:handle_frame, client, FrameStruct.new(:pong, nil, nil))

      assert_equal 12345.0, @adapter.instance_variable_get(:@last_received_at)
      assert_empty client.sent
    end

    should "notify connection_ended and log the close code for a close frame" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:info).with(regexp_matches(/1000/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:close, nil, 1000))

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "log 'none' instead of a blank code for a close frame without a status code" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:info).with(regexp_matches(/code none/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:close, nil, nil))
    end

    should "log and notify connection_ended instead of letting an exception escape to the gem" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      client = FakeClient.new
      client.stubs(:send).raises(IOError, "not opened for writing")
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/not opened for writing/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised do
        @adapter.send(:handle_frame, client, FrameStruct.new(:ping, "payload", nil))
      end
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end
  end

  context "watchdog_loop" do
    should "request a reconnect once the receive timeout has elapsed" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(131.0)

      @adapter.send(:watchdog_loop)

      assert @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "log a warning naming the actual elapsed seconds when reconnecting for inactivity" do
      @adapter.instance_variable_set(:@last_received_at, 100.0)
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(131.0)
      logger = mock("logger")
      logger.expects(:warn).with(regexp_matches(/no frame received for 31\.0s/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:watchdog_loop)
    end

    should "exit immediately when the connection has already ended, without waiting for the timeout" do
      @adapter.instance_variable_set(:@last_received_at, Process.clock_gettime(Process::CLOCK_MONOTONIC))
      queue = Queue.new
      queue.push(true)
      @adapter.instance_variable_set(:@connection_ended, queue)

      @adapter.send(:watchdog_loop)

      assert_not @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "exit immediately without polling the queue when already stopped" do
      @adapter.instance_variable_set(:@stopped, true)
      RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.expects(:timed_queue_pop).never

      @adapter.send(:watchdog_loop)
    end

    should "exit immediately without polling the queue when a reconnect was already requested" do
      @adapter.instance_variable_set(:@reconnect_requested, true)
      RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.expects(:timed_queue_pop).never

      @adapter.send(:watchdog_loop)
    end

    should "recompute the remaining wait when a frame arrives right at the deadline" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(100.0, 120.0)
      @adapter.instance_variable_set(:@last_received_at, 90.0)
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      remainings = []
      RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.stubs(:timed_queue_pop).with do |_queue, remaining|
        remainings << remaining
        @adapter.instance_variable_set(:@last_received_at, 115.0) if remainings.size == 1
        true
      end.returns(nil, true)

      @adapter.send(:watchdog_loop)

      assert_equal [ 20.0, 25.0 ], remainings
    end
  end

  context "send_frame" do
    should "hold send_mutex while sending through the client" do
      client = FakeClient.new
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      @adapter.send(:send_frame, client, "hello", type: :pong)

      assert_equal [ FakeClient::Sent.new("hello", :pong) ], client.sent
    end

    should "do nothing and raise no exception when the client is nil" do
      assert_nothing_raised do
        @adapter.send(:send_frame, nil, "hello")
      end
    end

    should "never let two threads send through the client at the same time" do
      client = ConcurrencyDetectingClient.new

      threads = 5.times.map { |i| Thread.new { @adapter.send(:send_frame, client, "msg#{i}") } }
      threads.each(&:join)

      assert_not client.overlap_detected
      assert_equal 5, client.calls.size
    end
  end

  context "close_socket" do
    should "close the socket while holding send_mutex" do
      ws = mock("ws")
      ws.expects(:close)
      @adapter.instance_variable_set(:@ws, ws)
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      @adapter.send(:close_socket)

      assert_nil @adapter.instance_variable_get(:@ws)
    end

    should "swallow IOError raised while closing" do
      ws = mock("ws")
      ws.expects(:close).raises(IOError, "closed stream")
      @adapter.instance_variable_set(:@ws, ws)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end

    should "swallow SystemCallError raised while closing" do
      ws = mock("ws")
      ws.expects(:close).raises(Errno::ECONNRESET)
      @adapter.instance_variable_set(:@ws, ws)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end

    should "do nothing when there is no socket to close" do
      assert_nil @adapter.instance_variable_get(:@ws)

      assert_nothing_raised { @adapter.send(:close_socket) }
    end
  end

  context "send_mutex reuse across reconnects (INV-4)" do
    should "keep the same send_mutex instance across two listen cycles" do
      ws = mock("ws")
      ws.stubs(:close)
      WebSocket::Client::Simple.stubs(:connect).returns(ws)
      @adapter.stubs(:watchdog_loop)
      original_mutex = @adapter.instance_variable_get(:@send_mutex)

      @adapter.send(:listen, "wss://one")
      assert_same original_mutex, @adapter.instance_variable_get(:@send_mutex)

      @adapter.send(:listen, "wss://two")
      assert_same original_mutex, @adapter.instance_variable_get(:@send_mutex)
    end
  end

  context "socket callbacks" do
    should "log the error and notify connection_ended on socket_errored" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/websocket error/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:socket_errored, StandardError.new("boom"))

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "notify connection_ended on connection_ended!" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)

      @adapter.send(:connection_ended!)

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end
  end

  context "error classification" do
    should "classify SlackApiError as a fatal config error" do
      error = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError.new("invalid_auth")

      assert @adapter.fatal_config_error?(error)
    end

    should "not classify generic errors as a fatal config error" do
      assert_not @adapter.fatal_config_error?(RuntimeError.new("boom"))
    end
  end

  # Records messages dispatched by the adapter in place of the gateway.
  class RecordingDispatcher
    attr_reader :messages

    def initialize
      @messages = []
    end

    def enqueue(_adapter, message)
      @messages << message
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

  # Doubles for the frames handle_frame receives (#type / #data / #code).
  FrameStruct = Struct.new(:type, :data, :code)

  # Detects whether two threads ever ran #send concurrently. Only safe as a
  # plain (unlocked) instance variable *because* that is exactly the property
  # under test: if send_frame's own @send_mutex serializes calls correctly,
  # this method's body never actually runs on two threads at once.
  class ConcurrencyDetectingClient
    attr_reader :overlap_detected, :calls

    def initialize
      @busy = false
      @overlap_detected = false
      @calls = []
    end

    def send(data, type: :text) # rubocop:disable Lint/UnusedMethodArgument
      @overlap_detected ||= @busy
      @busy = true
      sleep 0.01
      @calls << data
      @busy = false
    end
  end

  def events_envelope(event, envelope_id: "env-1")
    {
      "type" => "events_api",
      "envelope_id" => envelope_id,
      "payload" => { "event" => event }
    }.to_json
  end

  context "events_api envelopes" do
    setup do
      @dispatcher = RecordingDispatcher.new
      @adapter.dispatcher = @dispatcher
      @ws = mock("websocket")
      @adapter.instance_variable_set(:@ws, @ws)
      @adapter.instance_variable_set(:@bot_user_id, "B001")
    end

    should "ack immediately with the envelope_id" do
      @ws.expects(:send).with({ envelope_id: "env-42" }.to_json, type: :text)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "111.222", "text" => "<@B001> hello" },
        envelope_id: "env-42"
      ))
    end

    should "convert app_mention into an IncomingMessage without the mention" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "111.222", "text" => "<@B001> open issues?" }
      ))

      assert_equal 1, @dispatcher.messages.size
      message = @dispatcher.messages.first
      assert_equal "slack", message.channel_type
      assert_equal "C123", message.channel_id
      assert_equal "C123:111.222", message.thread_key
      assert_equal "111.222", message.message_ts
      assert_equal "open issues?", message.text
      assert_not message.dm?
    end

    should "use thread_ts for the thread_key but keep the individual message_ts" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "333.444", "thread_ts" => "111.222", "text" => "<@B001> more" }
      ))

      message = @dispatcher.messages.first
      assert_equal "C123:111.222", message.thread_key
      assert_equal "333.444", message.message_ts
    end

    should "mark a mention inside an existing thread as in_thread" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "333.444", "thread_ts" => "111.222", "text" => "<@B001> more" }
      ))

      assert_predicate @dispatcher.messages.first, :in_thread?
    end

    should "not mark a mention outside a thread as in_thread" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "111.222", "text" => "<@B001> open issues?" }
      ))

      assert_not_predicate @dispatcher.messages.first, :in_thread?
    end

    should "convert an im message into a dm IncomingMessage" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "message", "channel_type" => "im", "user" => "U123",
          "channel" => "D123", "ts" => "111.222", "text" => "hi there" }
      ))

      message = @dispatcher.messages.first
      assert message.dm?
      assert_equal "D123", message.channel_id
      assert_equal "hi there", message.text
    end

    should "discard bot messages, own messages and subtyped events" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "message", "channel_type" => "im", "bot_id" => "B999",
          "channel" => "D123", "ts" => "1.2", "text" => "from a bot" }
      ))
      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "B001", "channel" => "C123",
          "ts" => "1.2", "text" => "self mention" }
      ))
      @adapter.handle_envelope(events_envelope(
        { "type" => "message", "channel_type" => "im", "user" => "U123",
          "subtype" => "message_changed", "channel" => "D123", "ts" => "1.2", "text" => "edited" }
      ))
      @adapter.handle_envelope(events_envelope(
        { "type" => "reaction_added", "user" => "U123" }
      ))

      assert_empty @dispatcher.messages
    end
  end

  context "history retrieval" do
    setup do
      @adapter.instance_variable_set(:@bot_user_id, "B001")
      @adapter.instance_variable_set(:@bot_id, "BOT_ID")
    end

    should "declare history support" do
      assert_predicate @adapter, :supports_history?
    end

    should "ask conversations.replies for the messages after the cursor" do
      stub_slack_calls(replies_body([]))

      @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001", after: "100.000500")

      assert_equal [ "/api/conversations.replies" ], slack_paths
      form = slack_form(0)
      assert_equal "C1", form["channel"]
      assert_equal "100.000001", form["ts"]
      assert_equal "100.000500", form["oldest"]
      assert_equal "false", form["inclusive"]
      assert_equal "200", form["limit"]
    end

    should "omit oldest on the first import of a thread" do
      stub_slack_calls(replies_body([]))

      @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_not slack_form(0).key?("oldest")
    end

    should "return the messages in ascending order" do
      stub_slack_calls(
        replies_body([ slack_message(text: "second", ts: "2"), slack_message(text: "first", ts: "1") ]),
        user_info(display_name: "yamachan")
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal [ "first", "second" ], history.map(&:text)
    end

    should "follow the next_cursor pagination until it is empty" do
      stub_slack_calls(
        replies_body([ slack_message(text: "newest", ts: "3", user: nil, bot_id: "OTHER", username: "CI") ],
                     next_cursor: "page2"),
        replies_body([ slack_message(text: "older", ts: "1", user: nil, bot_id: "OTHER", username: "CI") ])
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal 2, slack_paths.size
      assert_not slack_form(0).key?("cursor")
      assert_equal "page2", slack_form(1)["cursor"]
      assert_equal [ "older", "newest" ], history.map(&:text)
    end

    should "raise when the history call fails" do
      stub_slack_calls({ "ok" => false, "error" => "missing_scope" })

      error = assert_raises(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError) do
        @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")
      end
      assert_match(/missing_scope/, error.message)
    end

    should "send oldest alongside cursor on paginated calls after the first import" do
      stub_slack_calls(
        replies_body([ slack_message(text: "newest", ts: "3", user: nil, bot_id: "OTHER", username: "CI") ],
                     next_cursor: "page2"),
        replies_body([ slack_message(text: "older", ts: "2", user: nil, bot_id: "OTHER", username: "CI") ])
      )

      @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001", after: "1")

      assert_equal 2, slack_paths.size
      assert_equal "1", slack_form(0)["oldest"], "oldest must be sent on every page"
      assert_equal "1", slack_form(1)["oldest"], "oldest must be preserved on the paginated call"
      assert_equal "page2", slack_form(1)["cursor"]
    end
  end

  context "channel history retrieval" do
    setup do
      @adapter.instance_variable_set(:@bot_user_id, "B001")
      @adapter.instance_variable_set(:@bot_id, "BOT_ID")
      @since = Time.zone.parse("2026-08-01 00:00:00")
    end

    should "ask conversations.history for the recent top-level messages" do
      stub_slack_calls({ "ok" => true, "messages" => [] })

      @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)

      assert_equal [ "/api/conversations.history" ], slack_paths
      form = slack_form(0)
      assert_equal "C1", form["channel"]
      assert_equal "100.000900", form["latest"]
      assert_equal @since.to_f.to_s, form["oldest"]
      assert_equal "false", form["inclusive"]
      assert_equal "20", form["limit"]
    end

    should "return the messages in ascending order" do
      stub_slack_calls(
        { "ok" => true, "messages" => [ slack_message(text: "second", ts: "2", user: nil, bot_id: "CI", username: "CI"),
                                        slack_message(text: "first", ts: "1", user: nil, bot_id: "CI", username: "CI") ] }
      )

      history = @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)

      assert_equal [ "first", "second" ], history.map(&:text)
    end

    should "apply the same exclusions as the thread history" do
      stub_slack_calls(
        { "ok" => true, "messages" => [ slack_message(text: "joined", subtype: "channel_join"),
                                        slack_message(text: "<@B001> question", ts: "2"),
                                        slack_message(text: "my answer", user: "B001", ts: "3") ] }
      )

      assert_empty @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)
    end

    should "return an empty array when the channel has no recent messages" do
      stub_slack_calls({ "ok" => true, "messages" => [] })

      assert_empty @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)
    end

    should "raise when the channel history call fails" do
      stub_slack_calls({ "ok" => false, "error" => "missing_scope" })

      assert_raises(RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::SlackApiError) do
        @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)
      end
    end

    should "resolve real user display names via users.info" do
      stub_slack_calls(
        { "ok" => true, "messages" => [ slack_message(text: "hello", user: "U1", ts: "1") ] },
        user_info(display_name: "yamachan")
      )

      history = @adapter.fetch_channel_history(channel_id: "C1", before: "100.000900", since: @since, limit: 20)

      assert_equal [ "yamachan" ], history.map(&:speaker)
      assert_equal [ "/api/conversations.history", "/api/users.info" ], slack_paths
    end
  end

  context "history filtering" do
    setup do
      @adapter.instance_variable_set(:@bot_user_id, "B001")
      @adapter.instance_variable_set(:@bot_id, "BOT_ID")
    end

    should "skip messages whose subtype is not on the allow list" do
      stub_slack_calls(
        replies_body([ slack_message(text: "joined the channel", subtype: "channel_join") ])
      )

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")
    end

    should "keep the allowed subtypes" do
      stub_slack_calls(
        replies_body([ slack_message(text: "shared a file", subtype: "file_share", user: nil,
                                     bot_id: "OTHER", username: "CI") ])
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal [ "shared a file" ], history.map(&:text)
    end

    should "skip the gateway's own messages" do
      stub_slack_calls(
        replies_body([ slack_message(text: "my own answer", user: "B001"),
                       slack_message(text: "posted as the app", user: nil, bot_id: "BOT_ID",
                                     subtype: "bot_message", username: "AI Helper") ])
      )

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")
    end

    should "skip questions addressed to the bot" do
      stub_slack_calls(
        replies_body([ slack_message(text: "<@B001> what about this?") ])
      )

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")
    end

    should "skip messages whose body is empty" do
      stub_slack_calls(
        replies_body([ slack_message(text: "   ") ])
      )

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")
    end

    should "import other bots with their display name" do
      stub_slack_calls(
        replies_body([ slack_message(text: "build failed", user: nil, bot_id: "CI_BOT",
                                     subtype: "bot_message", username: "CI notifier") ])
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal [ "CI notifier" ], history.map(&:speaker)
      assert_equal [ "/api/conversations.replies" ], slack_paths, "bot messages must not trigger users.info"
    end

    should "fall back to the bot profile name when a bot message has no username" do
      stub_slack_calls(
        replies_body([ slack_message(text: "build failed", user: nil, bot_id: "CI_BOT",
                                     subtype: "bot_message", bot_profile: { "name" => "CI profile" }) ])
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal [ "CI profile" ], history.map(&:speaker)
    end
  end

  context "speaker display names" do
    setup do
      @adapter.instance_variable_set(:@bot_user_id, "B001")
      @adapter.instance_variable_set(:@bot_id, "BOT_ID")
    end

    should "prefer the profile display name" do
      stub_slack_calls(
        replies_body([ slack_message(text: "hello") ]),
        user_info(display_name: "yamachan", real_name: "Yamada Taro", name: "yamada")
      )

      assert_equal [ "yamachan" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001").map(&:speaker)
    end

    should "fall back to the real name when the display name is empty" do
      stub_slack_calls(
        replies_body([ slack_message(text: "hello") ]),
        user_info(display_name: "", real_name: "Yamada Taro", name: "yamada")
      )

      assert_equal [ "Yamada Taro" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001").map(&:speaker)
    end

    should "fall back to the account name when display and real name are empty" do
      stub_slack_calls(
        replies_body([ slack_message(text: "hello") ]),
        user_info(display_name: "", real_name: "", name: "yamada")
      )

      assert_equal [ "yamada" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001").map(&:speaker)
    end

    should "resolve each user only once" do
      stub_slack_calls(
        replies_body([ slack_message(text: "second", ts: "2"), slack_message(text: "first", ts: "1") ]),
        user_info(display_name: "yamachan")
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:100.000001")

      assert_equal [ "yamachan", "yamachan" ], history.map(&:speaker)
      assert_equal [ "/api/conversations.replies", "/api/users.info" ], slack_paths
    end

    should "evict the oldest cached display name once the cap is exceeded" do
      cap = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::MAX_DISPLAY_NAMES
      (cap + 1).times { |i| @adapter.send(:cache_display_name, "U#{i}", "name#{i}") }

      cache = @adapter.instance_variable_get(:@display_names)
      assert_equal cap, cache.size
      assert_not cache.key?("U0"), "the oldest entry must be evicted"
      assert cache.key?("U#{cap}"), "the newest entry must be kept"
    end
  end

  context "web api operations" do
    should "post the reply into the thread" do
      @adapter.expects(:api_call).with(
        "chat.postMessage",
        token: "xoxb-secret",
        params: { channel: "C123", thread_ts: "111.222", text: "the answer" }
      ).returns({ "ok" => true })

      @adapter.send_message(channel_id: "C123", thread_key: "C123:111.222", text: "the answer")
    end

    should "split long replies at paragraph boundaries" do
      first = "a" * 3000
      second = "b" * 2000
      text = "#{first}\n\n#{second}"
      calls = sequence("posts")
      @adapter.expects(:api_call).with(
        "chat.postMessage", token: "xoxb-secret",
        params: { channel: "C123", thread_ts: "1.2", text: first }
      ).in_sequence(calls).returns({ "ok" => true })
      @adapter.expects(:api_call).with(
        "chat.postMessage", token: "xoxb-secret",
        params: { channel: "C123", thread_ts: "1.2", text: second }
      ).in_sequence(calls).returns({ "ok" => true })

      @adapter.send_message(channel_id: "C123", thread_key: "C123:1.2", text: text)
    end

    should "split on single newlines when there is no paragraph boundary" do
      first = "a" * 3000
      second = "b" * 2000
      text = "#{first}\n#{second}"

      chunks = @adapter.send(:split_text, text)

      assert_equal [ first, second ], chunks
    end

    should "force-split when there is no newline at all" do
      text = "a" * 8000

      chunks = @adapter.send(:split_text, text)

      assert_equal [ 3900, 3900, 200 ], chunks.map(&:length)
      assert_equal text, chunks.join
    end
  end

  context "issue link format" do
    should "V-19: return SLACK format" do
      assert_equal RedmineAiHelper::ChatChannel::IssueLinkFormatter::SLACK,
                   @adapter.issue_link_format
    end

    should "V-21: not cut a link syntax when the forced cut falls inside it" do
      link = "<https://r.example.com/issues/1549|#1549>"
      pad_before = "x" * (RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::MAX_MESSAGE_LENGTH - 10)
      text = "#{pad_before}#{link}"

      chunks = @adapter.send(:split_text, text)

      assert chunks.length >= 2, "text must exceed MAX_MESSAGE_LENGTH"
      assert chunks.any? { |c| c.include?(link) },
             "the link must survive intact in a single chunk"
      assert_equal pad_before, chunks.first
      assert chunks.last.start_with?(link)
    end

    should "V-22: split at newline boundaries as before" do
      first = "a" * 3000
      second = "b" * 2000
      text = "#{first}\n\n#{second}"

      chunks = @adapter.send(:split_text, text)

      assert_equal [ first, second ], chunks
    end

    should "V-23: produce a finite number of chunks for a single link exceeding MAX_MESSAGE_LENGTH at offset 0" do
      long_url = "https://r.example.com/issues/#{'1' * (RedmineAiHelper::ChatChannel::Adapters::SlackAdapter::MAX_MESSAGE_LENGTH)}"
      link = "<#{long_url}|#1>"
      text = link

      chunks = @adapter.send(:split_text, text)

      assert chunks.length < 50, "must terminate without infinite loop"
      assert_equal text, chunks.join
    end
  end
end
