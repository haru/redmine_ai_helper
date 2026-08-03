# frozen_string_literal: true

require File.expand_path("../../../../test_helper", __FILE__)

class ChatChannelDiscordAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  DiscordAdapter = RedmineAiHelper::ChatChannel::Adapters::DiscordAdapter
  DiscordApiError = DiscordAdapter::DiscordApiError
  DiscordRequestError = DiscordAdapter::DiscordRequestError
  IncomingMessage = RedmineAiHelper::ChatChannel::IncomingMessage

  BOT_TOKEN = "discord-bot-secret"

  setup do
    AiHelperChatAdapterSetting.delete_all
    create(:ai_helper_chat_adapter_setting,
           channel_type: "discord", enabled: true, bot_token: BOT_TOKEN, redmine_user_id: 2,
           default_project_id: 1)
    @adapter = DiscordAdapter.new
    @adapter.instance_variable_set(:@bot_user_id, "BOT")
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
  # under test: if the shared send mutex serializes calls correctly, this
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

  def http_response(code, body)
    stub(code: code.to_s, body: body.to_json)
  end

  # Answers the REST calls with the given bodies in call order and records the
  # requests so their paths and query strings can be asserted.
  def stub_discord_calls(*bodies)
    @discord_requests = []
    responses = bodies.map { |body| http_response(200, body) }
    Net::HTTP.any_instance.stubs(:request).with { |request| @discord_requests << request; true }
             .returns(*responses)
  end

  def discord_paths
    @discord_requests.map(&:path)
  end

  def discord_query(index)
    URI.decode_www_form(URI(@discord_requests[index].path).query.to_s).to_h
  end

  def history_raw(content:, id: "100", type: 0, author_id: "U1", username: "yamada",
                  global_name: nil, nick: nil, timestamp: "2026-08-01T00:00:00.000000+00:00")
    message = {
      "id" => id, "type" => type, "content" => content, "timestamp" => timestamp,
      "author" => { "id" => author_id, "username" => username }
    }
    message["author"]["global_name"] = global_name if global_name
    message["member"] = { "nick" => nick } if nick
    message
  end

  def guild_message(content:, id: "M1", channel_id: "C1", type: 0, author_id: "U1",
                    bot: false, guild_id: "G1", ref: nil, mentions: nil)
    message = {
      "id" => id, "channel_id" => channel_id, "type" => type, "guild_id" => guild_id,
      "content" => content, "author" => { "id" => author_id, "bot" => bot }
    }
    message["message_reference"] = { "message_id" => ref } if ref
    message["mentions"] = mentions if mentions
    message
  end

  def dm_message(content:, id: "M1", channel_id: "D1", type: 0, author_id: "U1", bot: false, ref: nil)
    message = {
      "id" => id, "channel_id" => channel_id, "type" => type,
      "content" => content, "author" => { "id" => author_id, "bot" => bot }
    }
    message["message_reference"] = { "message_id" => ref } if ref
    message
  end

  context "registration and settings" do
    should "declare channel_type discord and register itself" do
      assert_equal "discord", DiscordAdapter.channel_type
      assert_equal DiscordAdapter,
                   RedmineAiHelper::ChatChannel::BaseAdapter.adapters["discord"]
    end

    should "require only the bot token" do
      assert_equal [ :bot_token ], DiscordAdapter.required_setting_fields
    end

    should "be enabled with only the bot token present (no app_token)" do
      assert_predicate @adapter, :enabled?
    end
  end

  context "error classification" do
    should "classify DiscordApiError as a fatal config error" do
      assert @adapter.fatal_config_error?(DiscordApiError.new("unauthorized"))
    end

    should "not classify DiscordRequestError or generic errors as fatal" do
      assert_not @adapter.fatal_config_error?(DiscordRequestError.new("boom", status: 500))
      assert_not @adapter.fatal_config_error?(RuntimeError.new("boom"))
    end
  end

  context "rest api" do
    should "configure open and read timeouts of 10 seconds" do
      http = @adapter.send(:build_http, URI("#{DiscordAdapter::DISCORD_API_BASE}/users/@me"))

      assert_equal 10, http.open_timeout
      assert_equal 10, http.read_timeout
    end

    should "authenticate with the bot token" do
      request = @adapter.send(:build_request, :get, URI("#{DiscordAdapter::DISCORD_API_BASE}/users/@me"), nil)

      assert_equal "Bot #{BOT_TOKEN}", request["Authorization"]
    end

    should "return the parsed body on success" do
      Net::HTTP.any_instance.stubs(:request).returns(http_response(200, { "id" => "B1" }))

      assert_equal "B1", @adapter.send(:request, :get, "/users/@me")["id"]
    end

    should "raise DiscordApiError on 401 without retry or leaking the token" do
      Net::HTTP.any_instance.expects(:request).once.returns(http_response(401, { "message" => "401: Unauthorized" }))

      error = assert_raises(DiscordApiError) { @adapter.send(:request, :get, "/users/@me") }
      assert_no_match(/#{Regexp.escape(BOT_TOKEN)}/, error.message)
    end

    should "wait retry_after and resend on 429, then succeed" do
      calls = sequence("http")
      Net::HTTP.any_instance.expects(:request).twice.in_sequence(calls).returns(
        http_response(429, { "retry_after" => 0.01 }),
        http_response(200, { "id" => "B1" })
      )
      @adapter.stubs(:sleep)

      assert_equal "B1", @adapter.send(:request, :get, "/users/@me")["id"]
    end

    should "raise DiscordRequestError after exhausting the 429 retry cap" do
      Net::HTTP.any_instance.stubs(:request).returns(http_response(429, { "retry_after" => 0.01 }))
      @adapter.stubs(:sleep)

      assert_raises(DiscordRequestError) { @adapter.send(:request, :get, "/users/@me") }
    end

    should "log a warning and fall back to 1 second when the 429 body cannot be parsed" do
      response = http_response(429, {})
      response.stubs(:body).returns("not json")
      logger = mock("logger")
      logger.expects(:warn).with(regexp_matches(/retry_after/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_equal 1.0, @adapter.send(:retry_after_seconds, response)
    end

    should "raise DiscordRequestError with the status and code on other 4xx" do
      Net::HTTP.any_instance.stubs(:request).returns(http_response(400, { "code" => 50035, "message" => "Invalid" }))

      error = assert_raises(DiscordRequestError) { @adapter.send(:request, :post, "/channels/C1/messages", body: {}) }
      assert_equal 400, error.status
      assert_equal 50035, error.code
    end
  end

  context "connection lifecycle" do
    should "fetch the bot user id via /users/@me" do
      @adapter.expects(:request).with(:get, "/users/@me").returns({ "id" => "B1" })

      assert_equal "B1", @adapter.send(:fetch_bot_user_id)
    end

    should "obtain the gateway url via /gateway/bot" do
      @adapter.expects(:request).with(:get, "/gateway/bot").returns({ "url" => "wss://gw" })

      assert_equal "wss://gw", @adapter.send(:gateway_url)
    end

    should "connect the websocket with the required v and encoding query params" do
      @adapter.stubs(:watchdog_loop)
      ws = mock("ws")
      ws.stubs(:on)
      ws.stubs(:close)
      WebSocket::Client::Simple.expects(:connect).with("wss://gw?v=10&encoding=json").returns(ws)

      @adapter.send(:listen, "wss://gw")
    end

    should "terminate without retry when /users/@me returns 401" do
      @adapter.expects(:fetch_bot_user_id).raises(DiscordApiError, "unauthorized")
      @adapter.expects(:gateway_url).never

      assert_raises(DiscordApiError) { @adapter.start }
    end

    should "stop cleanly after fetching the bot user id" do
      @adapter.expects(:fetch_bot_user_id).returns("B1")
      @adapter.stubs(:gateway_url).returns("wss://gw")
      @adapter.stubs(:listen).with { @adapter.stop; true }

      @adapter.start

      assert_equal "B1", @adapter.bot_user_id
    end

    should "terminate #start without retry when the gateway closes with a fatal code" do
      @adapter.stubs(:fetch_bot_user_id).returns("B1")
      @adapter.expects(:gateway_url).once.returns("wss://gw")
      @adapter.stubs(:watchdog_loop).with { @adapter.send(:handle_close_frame, 4004); true }
      ws = mock("ws")
      ws.stubs(:on)
      ws.stubs(:close)
      WebSocket::Client::Simple.stubs(:connect).returns(ws)

      assert_raises(DiscordApiError) { @adapter.start }
    end

    should "C-1.9: terminate #start without retry when a fatal API error escapes frame handling" do
      # A token revoked mid-session makes the REST call that resolves the
      # channel raise. The error must not be turned into an immediate,
      # unthrottled reconnect: it terminates the adapter (ADR-006).
      @adapter.stubs(:fetch_bot_user_id).returns("B1")
      @adapter.expects(:gateway_url).once.returns("wss://gw")
      @adapter.stubs(:fetch_channel).raises(DiscordApiError, "unauthorized")
      ws = mock("ws")
      ws.stubs(:on)
      ws.stubs(:close)
      WebSocket::Client::Simple.stubs(:connect).returns(ws)
      frame = FrameStruct.new(:text, {
        op: DiscordAdapter::OP_DISPATCH, t: "MESSAGE_CREATE",
        d: guild_message(content: "<@B1> hello")
      }.to_json, nil)
      @adapter.stubs(:watchdog_loop).with { @adapter.send(:handle_frame, ws, frame); true }

      assert_raises(DiscordApiError) { @adapter.start }
    end

    should "C-1.9: record a DiscordApiError escaping frame handling as the fatal close" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      @adapter.stubs(:handle_gateway_message).raises(DiscordApiError, "unauthorized")

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:text, "{}", nil))

      assert_kind_of DiscordApiError, @adapter.instance_variable_get(:@fatal_close)
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "C-1.9: leave a transient error escaping frame handling non-fatal" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      @adapter.stubs(:handle_gateway_message).raises(DiscordRequestError.new("HTTP 500", status: 500))

      @adapter.send(:handle_frame, FakeClient.new, FrameStruct.new(:text, "{}", nil))

      assert_nil @adapter.instance_variable_get(:@fatal_close),
                 "a transient REST failure must not terminate the adapter"
      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "store the heartbeat interval and send Identify on Hello" do
      ws = mock("ws")
      ws.expects(:send).with do |raw|
        payload = JSON.parse(raw)
        payload["op"] == DiscordAdapter::OP_IDENTIFY &&
          payload["d"]["intents"] == DiscordAdapter::GATEWAY_INTENTS &&
          payload["d"]["token"] == BOT_TOKEN
      end
      @adapter.instance_variable_set(:@ws, ws)

      @adapter.handle_gateway_message(ws, { op: DiscordAdapter::OP_HELLO, d: { heartbeat_interval: 41250 } }.to_json)

      assert_in_delta 41.25, @adapter.instance_variable_get(:@heartbeat_interval), 0.001
    end

    should "mark connected and reset the backoff on READY" do
      3.times { @adapter.send(:next_backoff) }

      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_DISPATCH, t: "READY", s: 1, d: { "user" => { "id" => "B1" } } }.to_json)

      assert_predicate @adapter, :connected?
      assert_equal 1, @adapter.send(:next_backoff)
    end

    should "reply to a server heartbeat request immediately with the last sequence" do
      ws = mock("ws")
      ws.expects(:send).with { |raw| JSON.parse(raw) == { "op" => DiscordAdapter::OP_HEARTBEAT, "d" => 7 } }
      @adapter.instance_variable_set(:@ws, ws)
      @adapter.instance_variable_set(:@last_sequence, 7)

      @adapter.handle_gateway_message(ws, { op: DiscordAdapter::OP_HEARTBEAT }.to_json)
    end

    should "keep the last sequence number of every payload that carries one" do
      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HEARTBEAT_ACK, s: 12 }.to_json)

      assert_equal 12, @adapter.instance_variable_get(:@last_sequence)
    end

    should "keep the previous sequence number for a payload that carries none" do
      @adapter.instance_variable_set(:@last_sequence, 12)

      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HEARTBEAT_ACK }.to_json)

      assert_equal 12, @adapter.instance_variable_get(:@last_sequence)
    end

    should "record a sequence number of zero rather than treating it as absent" do
      @adapter.instance_variable_set(:@last_sequence, 12)

      # Discord numbers dispatches from 1, so this does not occur in practice;
      # the test pins down that only a missing "s" is skipped, since 0 is
      # truthy in Ruby and the check would otherwise be ambiguous.
      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HEARTBEAT_ACK, s: 0 }.to_json)

      assert_equal 0, @adapter.instance_variable_get(:@last_sequence)
    end

    should "request a reconnect on Reconnect (op 7) and Invalid Session (op 9)" do
      [ DiscordAdapter::OP_RECONNECT, DiscordAdapter::OP_INVALID_SESSION ].each do |op|
        adapter = DiscordAdapter.new
        adapter.instance_variable_set(:@connection_ended, Queue.new)

        adapter.handle_gateway_message(nil, { op: op }.to_json)

        assert adapter.instance_variable_get(:@reconnect_requested), "op #{op} must request reconnect"
      end
    end

    should "back off exponentially from 1 up to 60 seconds" do
      expected = [ 1, 2, 4, 8, 16, 32, 60, 60 ]

      assert_equal(expected, (1..8).map { @adapter.send(:next_backoff) })
    end

    should "capture a fatal DiscordApiError on authentication close codes" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)

      @adapter.handle_close_frame(4004)

      assert_kind_of DiscordApiError, @adapter.instance_variable_get(:@fatal_close)
    end

    should "C-6.5.1: log the fatal close code and end the connection" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:error).with("discord: gateway closed with fatal code 4014")
      @adapter.stubs(:ai_helper_logger).returns(logger)

      DiscordAdapter::FATAL_CLOSE_CODES.each do |code|
        adapter = DiscordAdapter.new
        adapter.instance_variable_set(:@connection_ended, Queue.new)

        adapter.handle_close_frame(code)

        assert_kind_of DiscordApiError, adapter.instance_variable_get(:@fatal_close),
                       "close code #{code} must be fatal"
      end

      @adapter.handle_close_frame(4014)

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "not capture a fatal error on a transient close code" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)

      @adapter.handle_close_frame(1006)

      assert_nil @adapter.instance_variable_get(:@fatal_close)
    end

    should "C-6.5.2: leave every other close code to the shared implementation" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:info).with("discord: close frame received (code 1006)")
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.handle_close_frame(1006)

      assert @adapter.instance_variable_get(:@connection_ended).pop(true)
    end

    should "evict the oldest reply target once the cap is exceeded, keeping recent ones" do
      cap = DiscordAdapter::MAX_REPLY_TARGETS
      (cap + 1).times { |i| @adapter.send(:record_reply_target, "key#{i}", "msg#{i}") }

      reply_targets = @adapter.instance_variable_get(:@reply_targets)
      assert_equal cap, reply_targets.size
      assert_not reply_targets.key?("key0"), "the oldest entry must be evicted"
      assert reply_targets.key?("key#{cap}"), "the newest entry must be kept"
    end
  end

  # US2: liveness is judged only by whether frames keep arriving. The bound
  # comes from the heartbeat interval Discord announces in Hello, so it
  # follows a changed interval instead of a hard-coded number.
  context "receive inactivity bound" do
    should "C-6.1.1 / SC-002: bound the silence at 1.5x the announced heartbeat interval" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)

      assert_in_delta 61.875, @adapter.send(:receive_timeout_seconds), 0.001
    end

    should "C-6.1.1: follow the announced interval instead of a fixed number" do
      @adapter.instance_variable_set(:@heartbeat_interval, 20.0)

      assert_in_delta 30.0, @adapter.send(:receive_timeout_seconds), 0.001

      @adapter.instance_variable_set(:@heartbeat_interval, 60.0)

      assert_in_delta 90.0, @adapter.send(:receive_timeout_seconds), 0.001
    end

    should "C-6.1.2: fall back to the shared default before Hello announces an interval" do
      assert_nil @adapter.instance_variable_get(:@heartbeat_interval)
      assert_equal DiscordAdapter::DEFAULT_RECEIVE_TIMEOUT_SECONDS,
                   @adapter.send(:receive_timeout_seconds)
      assert_equal 30, @adapter.send(:receive_timeout_seconds)
    end
  end

  # US2: the heartbeat Discord requires is sent as the monitor loop's
  # scheduled action, so no second thread ever writes to the socket.
  context "heartbeat scheduling" do
    should "C-6.2.1: set the next heartbeat time to one interval ahead on Hello" do
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0)
      @adapter.stubs(:send_identify)

      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HELLO, d: { heartbeat_interval: 41250 } }.to_json)

      assert_in_delta 41.25, @adapter.instance_variable_get(:@heartbeat_interval), 0.001
      assert_in_delta 1041.25, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.2.2: report the seconds left until the next heartbeat" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1041.25)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1030.0)

      assert_in_delta 11.25, @adapter.send(:next_scheduled_action_in), 0.001
    end

    should "C-6.2.2: poll every second while waiting for Hello" do
      assert_nil @adapter.instance_variable_get(:@heartbeat_interval)

      assert_equal DiscordAdapter::HELLO_WAIT_SECONDS, @adapter.send(:next_scheduled_action_in)
    end

    should "C-6.2.3 / INV-7: send the heartbeat once the scheduled time is reached and rearm it" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1000.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.5)
      @adapter.expects(:send_heartbeat).once

      @adapter.send(:perform_scheduled_action)

      assert_in_delta 1041.75, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.2.3 / INV-7: count the next heartbeat from now when the wake-up came late" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1000.0)
      # Woken up 7 seconds after the heartbeat was due (a blocking REST call on
      # the receive thread, a slow scheduler): the rhythm restarts from now
      # rather than compressing the following intervals to catch up.
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1007.0)
      @adapter.expects(:send_heartbeat).once

      @adapter.send(:perform_scheduled_action)

      assert_in_delta 1048.25, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.2.3: send no heartbeat once the adapter has been stopped" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1000.0)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.5)
      @adapter.instance_variable_set(:@stopped, true)
      @adapter.expects(:send_heartbeat).never

      @adapter.send(:perform_scheduled_action)

      assert_in_delta 1000.0, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.2.3: not send a heartbeat before the scheduled time, so short waits do not add up" do
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1041.25)
      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1020.0)
      @adapter.expects(:send_heartbeat).never

      @adapter.send(:perform_scheduled_action)

      assert_in_delta 1041.25, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.2.4: send nothing while the heartbeat interval is unknown" do
      @adapter.expects(:send_heartbeat).never

      @adapter.send(:perform_scheduled_action)

      assert_nil @adapter.instance_variable_get(:@next_heartbeat_at)
    end

    should "FR-009: keep the heartbeat payload unchanged (op 1 with the last sequence)" do
      client = FakeClient.new
      @adapter.instance_variable_set(:@ws, client)
      @adapter.instance_variable_set(:@last_sequence, 42)

      @adapter.send(:send_heartbeat, client)

      assert_equal([ { "op" => DiscordAdapter::OP_HEARTBEAT, "d" => 42 } ],
                   client.sent.map { |frame| JSON.parse(frame.data) })
    end
  end

  # US2: acks are no longer counted. An ack is just another received frame,
  # and a connection that stops answering is caught by the inactivity bound.
  context "heartbeat acknowledgement" do
    should "C-6.4.1: treat a heartbeat ack as a plain received frame" do
      @adapter.instance_variable_set(:@ws, FakeClient.new)
      @adapter.instance_variable_set(:@connection_ended, Queue.new)

      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HEARTBEAT_ACK }.to_json)

      assert_empty @adapter.instance_variable_get(:@ws).sent
      assert_not @adapter.instance_variable_get(:@reconnect_requested)
      assert @adapter.instance_variable_get(:@connection_ended).empty?
    end

    should "C-6.4.2: not track acks at all" do
      @adapter.handle_gateway_message(nil, { op: DiscordAdapter::OP_HEARTBEAT_ACK }.to_json)

      assert_not @adapter.instance_variables.include?(:@heartbeat_acked)
    end

    should "C-6.4.3 / FR-008: have no zombie-connection path that reconnects on a missing ack" do
      assert_not @adapter.respond_to?(:heartbeat_loop, true),
                 "the ack-counting loop must be replaced by the shared receive-inactivity watchdog"
    end
  end

  # US3: a frame is answered on the connection it arrived on. @ws is assigned
  # only after WebSocket::Client::Simple.connect returns, and Discord's very
  # first frame is Hello, so anything sent through @ws in that window would be
  # dropped silently - and a gateway that never receives Identify closes the
  # connection.
  context "answering on the arriving connection" do
    should "C-6.3.1: hand a text frame to the gateway parser together with its client" do
      client = FakeClient.new
      @adapter.expects(:handle_gateway_message).with(client, "raw payload")

      @adapter.send(:handle_text_frame, client, "raw payload")
    end

    should "C-6.3.2 / INV-6: send Identify to the arriving connection while @ws is still nil" do
      client = FakeClient.new
      assert_nil @adapter.instance_variable_get(:@ws)

      @adapter.handle_gateway_message(client, { op: DiscordAdapter::OP_HELLO, d: { heartbeat_interval: 41250 } }.to_json)

      assert_nil @adapter.instance_variable_get(:@ws), "the pre-handshake window must not be papered over with @ws"
      assert_equal([ DiscordAdapter::OP_IDENTIFY ], client.sent.map { |frame| JSON.parse(frame.data)["op"] })
    end

    should "C-6.2.5: answer a heartbeat request on the arriving connection without moving the schedule" do
      client = FakeClient.new
      @adapter.instance_variable_set(:@heartbeat_interval, 41.25)
      @adapter.instance_variable_set(:@next_heartbeat_at, 1041.25)
      @adapter.instance_variable_set(:@last_sequence, 9)

      @adapter.handle_gateway_message(client, { op: DiscordAdapter::OP_HEARTBEAT }.to_json)

      assert_equal([ { "op" => DiscordAdapter::OP_HEARTBEAT, "d" => 9 } ],
                   client.sent.map { |frame| JSON.parse(frame.data) })
      assert_in_delta 1041.25, @adapter.instance_variable_get(:@next_heartbeat_at), 0.001
    end

    should "C-6.3.3 / FR-017: keep the Identify payload exactly as it was" do
      client = FakeClient.new

      @adapter.send(:send_identify, client)

      payload = JSON.parse(client.sent.first.data)
      assert_equal DiscordAdapter::OP_IDENTIFY, payload["op"]
      assert_equal BOT_TOKEN, payload["d"]["token"]
      assert_equal 37376, payload["d"]["intents"]
      assert_equal({ "os" => "linux", "browser" => "redmine_ai_helper", "device" => "redmine_ai_helper" },
                   payload["d"]["properties"])
    end

    should "C-6.3.4: log a payload that cannot be parsed and keep the connection" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/failed to parse gateway payload/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      assert_nothing_raised { @adapter.handle_gateway_message(FakeClient.new, "not json") }

      assert @adapter.instance_variable_get(:@connection_ended).empty?
    end
  end

  # US1: every write to the gateway socket - Identify, heartbeats, the answer
  # to a heartbeat request and the close frame - goes through the single
  # serialized send path in BaseAdapter, so two of them can never interleave
  # and corrupt the connection.
  context "send serialization" do
    should "C-3.2: send Identify through the shared serialized send_frame" do
      ws = mock("ws")
      @adapter.instance_variable_set(:@ws, ws)
      @adapter.expects(:send_frame).with do |client, data|
        client == ws && JSON.parse(data)["op"] == DiscordAdapter::OP_IDENTIFY
      end

      @adapter.send(:send_identify, ws)
    end

    should "C-3.2: send heartbeats through the shared serialized send_frame" do
      ws = mock("ws")
      @adapter.instance_variable_set(:@ws, ws)
      @adapter.instance_variable_set(:@last_sequence, 7)
      @adapter.expects(:send_frame).with do |client, data|
        client == ws && JSON.parse(data) == { "op" => DiscordAdapter::OP_HEARTBEAT, "d" => 7 }
      end

      @adapter.send(:send_heartbeat, ws)
    end

    should "C-3.1 / SC-001: never let two sending threads overlap on the socket" do
      client = ConcurrencyDetectingClient.new
      @adapter.instance_variable_set(:@ws, client)

      threads = 6.times.map do |i|
        Thread.new { i.even? ? @adapter.send(:send_identify, client) : @adapter.send(:send_heartbeat, client) }
      end
      threads.each(&:join)

      assert_not client.overlap_detected
      assert_equal 6, client.calls.size
      # Complements overlap_detected: a truncated payload is what an interleaved
      # write would leave behind if the overlap itself went unobserved.
      assert client.calls.all? { |raw| JSON.parse(raw).key?("op") }, "no payload may be cut in half"
    end

    should "C-3.4 / FR-003: close the socket under the same mutex that serializes sends" do
      ws = mock("ws")
      ws.expects(:close)
      @adapter.instance_variable_set(:@ws, ws)
      mutex = @adapter.instance_variable_get(:@send_mutex)
      mutex.expects(:synchronize).yields

      @adapter.send(:close_socket)

      assert_nil @adapter.instance_variable_get(:@ws)
    end

    should "FR-002: have no unserialized send path left" do
      assert_not @adapter.respond_to?(:send_json, true),
                 "send_json bypassed the send mutex and must be gone"
    end
  end

  context "message selection" do
    setup do
      @dispatcher = RecordingDispatcher.new
      @adapter.dispatcher = @dispatcher
    end

    should "ignore messages from bots" do
      @adapter.send(:process_message, guild_message(content: "<@BOT> hi", bot: true))

      assert_empty @dispatcher.messages
    end

    should "ignore the bot's own messages" do
      @adapter.send(:process_message, guild_message(content: "<@BOT> hi", author_id: "BOT"))

      assert_empty @dispatcher.messages
    end

    should "ignore non-default, non-reply message types" do
      @adapter.send(:process_message, guild_message(content: "<@BOT> hi", type: 6))

      assert_empty @dispatcher.messages
    end

    should "ignore guild messages that do not mention the bot in the content" do
      @adapter.expects(:fetch_channel).never

      @adapter.send(:process_message, guild_message(content: "just chatting", mentions: [ { "id" => "BOT" } ]))

      assert_empty @dispatcher.messages
    end

    should "accept an explicit guild mention and strip the mention markup" do
      @adapter.stubs(:fetch_channel).returns({ "type" => 0 })
      @adapter.stubs(:create_thread).returns("M1")

      @adapter.send(:process_message, guild_message(content: "<@BOT> open issues?"))

      message = @dispatcher.messages.first
      assert_equal "discord", message.channel_type
      assert_equal "C1", message.channel_id
      assert_equal "C1:M1", message.thread_key
      assert_equal "M1", message.message_ts
      assert_equal "open issues?", message.text
      assert_not message.dm?
    end

    should "accept every DM as a question" do
      @adapter.send(:process_message, dm_message(content: "hello there"))

      message = @dispatcher.messages.first
      assert message.dm?
      assert_equal "D1", message.channel_id
      assert_equal "D1:msg:M1", message.thread_key
      assert_equal "hello there", message.text
    end
  end

  context "thread creation" do
    setup do
      @dispatcher = RecordingDispatcher.new
      @adapter.dispatcher = @dispatcher
    end

    should "create a thread for a new mention in a normal channel" do
      @adapter.stubs(:fetch_channel).returns({ "type" => 0 })
      @adapter.expects(:create_thread).with("C1", "M1", "open issues?").returns("M1")

      @adapter.send(:process_message, guild_message(content: "<@BOT> open issues?"))

      assert_equal "C1:M1", @dispatcher.messages.first.thread_key
    end

    should "treat an already-existing thread as success on the same thread_key" do
      @adapter.stubs(:request).raises(DiscordRequestError.new("exists", status: 400, code: DiscordAdapter::THREAD_ALREADY_EXISTS_CODE))

      assert_equal "M1", @adapter.send(:create_thread, "C1", "M1", "q")
    end

    should "fall back to nil when thread creation is forbidden" do
      @adapter.stubs(:request).raises(DiscordRequestError.new("forbidden", status: 403, code: 50013))

      assert_nil @adapter.send(:create_thread, "C1", "M1", "q")
    end

    should "fall back to nil when thread creation fails with a non-Discord error (e.g. a timeout)" do
      @adapter.stubs(:request).raises(Net::OpenTimeout, "execution expired")

      assert_nil @adapter.send(:create_thread, "C1", "M1", "q")
    end

    should "propagate a fatal DiscordApiError from thread creation instead of falling back" do
      @adapter.stubs(:request).raises(DiscordApiError, "unauthorized")

      assert_raises(DiscordApiError) { @adapter.send(:create_thread, "C1", "M1", "q") }
    end

    should "dispatch in reply mode when the thread cannot be created" do
      @adapter.stubs(:fetch_channel).returns({ "type" => 0 })
      @adapter.stubs(:create_thread).returns(nil)

      @adapter.send(:process_message, guild_message(content: "<@BOT> help"))

      message = @dispatcher.messages.first
      assert_equal "C1:msg:M1", message.thread_key
      assert_equal "C1", message.channel_id
    end
  end

  context "channel lookup failures" do
    setup do
      @dispatcher = RecordingDispatcher.new
      @adapter.dispatcher = @dispatcher
    end

    should "log a warning and drop the message when the channel lookup fails" do
      @adapter.stubs(:fetch_channel).raises(DiscordRequestError.new("boom", status: 500))
      logger = mock("logger")
      logger.expects(:warn).with(regexp_matches(/failed to fetch channel/))
      @adapter.stubs(:ai_helper_logger).returns(logger)

      @adapter.send(:process_message, guild_message(content: "<@BOT> hi"))

      assert_empty @dispatcher.messages
    end

    should "propagate a fatal DiscordApiError from the channel lookup instead of dropping the message" do
      @adapter.stubs(:fetch_channel).raises(DiscordApiError, "unauthorized")

      assert_raises(DiscordApiError) { @adapter.send(:process_message, guild_message(content: "<@BOT> hi")) }
    end
  end

  context "thread and dm continuation" do
    setup do
      @dispatcher = RecordingDispatcher.new
      @adapter.dispatcher = @dispatcher
    end

    should "continue inside an existing thread resolving the parent channel" do
      @adapter.stubs(:fetch_channel).returns({ "type" => 11, "parent_id" => "P1" })

      @adapter.send(:process_message, guild_message(content: "<@BOT> more", channel_id: "T1"))

      message = @dispatcher.messages.first
      assert_equal "P1", message.channel_id
      assert_equal "P1:T1", message.thread_key
    end

    should "mark a mention inside a thread channel as in_thread" do
      DiscordAdapter::THREAD_CHANNEL_TYPES.each do |channel_type|
        dispatcher = RecordingDispatcher.new
        @adapter.dispatcher = dispatcher
        @adapter.stubs(:fetch_channel).returns({ "type" => channel_type, "parent_id" => "P1" })

        @adapter.send(:process_message, guild_message(content: "<@BOT> more", channel_id: "T1"))

        assert_predicate dispatcher.messages.first, :in_thread?
      end
    end

    should "not mark a mention in a normal channel as in_thread" do
      @adapter.stubs(:fetch_channel).returns({ "type" => 0 })
      @adapter.stubs(:create_thread).returns("M1")

      @adapter.send(:process_message, guild_message(content: "<@BOT> hi"))

      assert_not_predicate @dispatcher.messages.first, :in_thread?
    end

    should "not mark a direct message as in_thread" do
      @adapter.send(:process_message, dm_message(id: "C", content: "hi"))

      assert_not_predicate @dispatcher.messages.first, :in_thread?
    end

    should "resolve a DM reply to a bot answer to the conversation root" do
      @adapter.stubs(:fetch_message).with("D1", "B").returns(
        { "id" => "B", "author" => { "id" => "BOT" }, "message_reference" => { "message_id" => "A" } }
      )
      @adapter.stubs(:fetch_message).with("D1", "A").returns({ "id" => "A", "author" => { "id" => "U1" } })

      @adapter.send(:process_message, dm_message(id: "C", content: "more", ref: "B"))

      assert_equal "D1:msg:A", @dispatcher.messages.first.thread_key
    end

    should "start a new DM conversation when replying to a non-bot message" do
      @adapter.stubs(:fetch_message).with("D1", "X").returns({ "id" => "X", "author" => { "id" => "U9" } })

      @adapter.send(:process_message, dm_message(id: "C", content: "more", ref: "X"))

      assert_equal "D1:msg:C", @dispatcher.messages.first.thread_key
    end

    should "start a new DM conversation when the referenced message cannot be fetched" do
      @adapter.stubs(:fetch_message).raises(DiscordRequestError.new("gone", status: 404))

      @adapter.send(:process_message, dm_message(id: "C", content: "more", ref: "Z"))

      assert_equal "D1:msg:C", @dispatcher.messages.first.thread_key
    end

    should "stop walking the reply chain at the hop limit instead of recursing forever" do
      limit = DiscordAdapter::MAX_REPLY_CHAIN_HOPS
      # message "0" has no reference (the true root); "1".."limit+1" each
      # reference the previous one, so the chain is longer than the limit.
      @adapter.stubs(:fetch_message).with("D1", "0").returns({ "id" => "0", "author" => { "id" => "BOT" } })
      (1..(limit + 1)).each do |i|
        @adapter.stubs(:fetch_message).with("D1", i.to_s).returns(
          { "id" => i.to_s, "author" => { "id" => "BOT" }, "message_reference" => { "message_id" => (i - 1).to_s } }
        )
      end

      @adapter.send(:process_message, dm_message(id: "C", content: "more", ref: (limit + 1).to_s))

      assert_equal "D1:msg:1", @dispatcher.messages.first.thread_key
    end
  end

  context "send_message" do
    should "post into the thread without a reference in thread mode" do
      @adapter.expects(:post_message).with("T1", { content: "answer" })

      @adapter.send_message(channel_id: "C1", thread_key: "C1:T1", text: "answer")
    end

    should "reference the recorded question message in reply mode" do
      @adapter.send(:record_reply_target, "D1:msg:A", "Q9")
      @adapter.expects(:post_message).with("D1", { content: "answer", message_reference: { message_id: "Q9" } })

      @adapter.send_message(channel_id: "D1", thread_key: "D1:msg:A", text: "answer")
    end

    should "fall back to the root id when no reply target is recorded" do
      @adapter.expects(:post_message).with("D1", { content: "answer", message_reference: { message_id: "A" } })

      @adapter.send_message(channel_id: "D1", thread_key: "D1:msg:A", text: "answer")
    end

    should "split long replies, referencing only the first chunk" do
      first = "a" * 1000
      second = "b" * 1500
      @adapter.send(:record_reply_target, "D1:msg:A", "Q")
      calls = sequence("posts")
      @adapter.expects(:post_message).with("D1", { content: first, message_reference: { message_id: "Q" } }).in_sequence(calls)
      @adapter.expects(:post_message).with("D1", { content: second }).in_sequence(calls)

      @adapter.send_message(channel_id: "D1", thread_key: "D1:msg:A", text: "#{first}\n\n#{second}")
    end

    should "force-split when there is no newline and lose no content" do
      text = "a" * 4000

      chunks = @adapter.send(:split_text, text)

      assert_equal [ 1900, 1900, 200 ], chunks.map(&:length)
      assert_equal text, chunks.join
    end
  end

  context "issue link format" do
    should "V-19: return DISCORD format" do
      assert_equal RedmineAiHelper::ChatChannel::IssueLinkFormatter::DISCORD,
                   @adapter.issue_link_format
    end

    should "V-21: not cut a link syntax when the forced cut falls inside it" do
      link = "[#1549](https://r.example.com/issues/1549)"
      pad_before = "x" * (RedmineAiHelper::ChatChannel::Adapters::DiscordAdapter::MAX_MESSAGE_LENGTH - 10)
      text = "#{pad_before}#{link}"

      chunks = @adapter.send(:split_text, text)

      assert chunks.length >= 2, "text must exceed MAX_MESSAGE_LENGTH"
      assert chunks.any? { |c| c.include?(link) },
             "the link must survive intact in a single chunk"
      assert_equal pad_before, chunks.first
      assert chunks.last.start_with?(link)
    end

    should "V-22: split at newline boundaries as before" do
      first = "a" * 1000
      second = "b" * 1500
      text = "#{first}\n\n#{second}"

      chunks = @adapter.send(:split_text, text)

      assert_equal [ first, second ], chunks
    end

    should "V-23: produce a finite number of chunks for a single link exceeding MAX_MESSAGE_LENGTH at offset 0" do
      long_url = "https://r.example.com/issues/#{'1' * (RedmineAiHelper::ChatChannel::Adapters::DiscordAdapter::MAX_MESSAGE_LENGTH)}"
      link = "[#1](#{long_url})"
      text = link

      chunks = @adapter.send(:split_text, text)

      assert chunks.length < 50, "must terminate without infinite loop"
      assert_equal text, chunks.join
    end
  end

  context "history retrieval" do
    should "declare history support" do
      assert_predicate @adapter, :supports_history?
    end

    should "identify with the privileged MESSAGE_CONTENT intent the import depends on" do
      assert_equal 4608 | (1 << 15), DiscordAdapter::GATEWAY_INTENTS
    end

    should "treat a disallowed intent as a fatal configuration error" do
      assert_includes DiscordAdapter::FATAL_CLOSE_CODES, 4014
    end

    should "read the thread messages with the page limit" do
      stub_discord_calls([])

      @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")

      assert_equal [ "/api/v10/channels/T1/messages?limit=100" ], discord_paths
    end

    should "return the messages in ascending order" do
      stub_discord_calls([ history_raw(content: "second", id: "20"), history_raw(content: "first", id: "10") ])

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")

      assert_equal [ "first", "second" ], history.map(&:text)
    end

    should "page backwards with before until a short page is returned" do
      stub_discord_calls(
        Array.new(100) { |i| history_raw(content: "message #{200 - i}", id: (200 - i).to_s) },
        [ history_raw(content: "message 1", id: "1") ]
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")

      assert_equal 2, discord_paths.size
      assert_equal "101", discord_query(1)["before"]
      assert_equal 101, history.size
      assert_equal "message 1", history.first.text
    end

    should "stop paging as soon as the cursor is reached" do
      stub_discord_calls(
        Array.new(100) { |i| history_raw(content: "message #{200 - i}", id: (200 - i).to_s) },
        [ history_raw(content: "message 1", id: "1") ]
      )

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1", after: "150")

      assert_equal 1, discord_paths.size, "the cursor must end the pagination"
      assert_equal 50, history.size
      assert_equal "message 151", history.first.text
    end

    should "exclude the cursor message itself" do
      stub_discord_calls([ history_raw(content: "newer", id: "20"), history_raw(content: "cursor", id: "10") ])

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1", after: "10")

      assert_equal [ "newer" ], history.map(&:text)
    end

    should "raise when the history call fails" do
      Net::HTTP.any_instance.stubs(:request).returns(http_response(403, { "message" => "Missing Access" }))

      assert_raises(DiscordRequestError) do
        @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")
      end
    end
  end

  context "channel history retrieval" do
    setup do
      @since = Time.zone.parse("2026-08-01 00:00:00")
    end

    should "read the channel messages with the requested limit and before cursor" do
      stub_discord_calls([])

      @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)

      assert_equal [ "/api/v10/channels/C1/messages?limit=20&before=900" ], discord_paths
    end

    should "return the messages in ascending order" do
      stub_discord_calls([ history_raw(content: "second", id: "20", timestamp: "2026-08-01T10:00:00+00:00"),
                           history_raw(content: "first", id: "10", timestamp: "2026-08-01T09:00:00+00:00") ])

      history = @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)

      assert_equal [ "first", "second" ], history.map(&:text)
    end

    should "drop messages older than the retrieval window" do
      stub_discord_calls([ history_raw(content: "recent", id: "20", timestamp: "2026-08-01T10:00:00+00:00"),
                           history_raw(content: "too old", id: "10", timestamp: "2026-07-29T10:00:00+00:00") ])

      history = @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)

      assert_equal [ "recent" ], history.map(&:text)
    end

    should "include a message whose timestamp is exactly at the since boundary" do
      boundary_ts = "2026-08-01T00:00:00.000000+00:00"
      stub_discord_calls([ history_raw(content: "at boundary", id: "10", timestamp: boundary_ts) ])

      history = @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)

      assert_equal [ "at boundary" ], history.map(&:text)
    end

    should "apply the same exclusions as the thread history" do
      stub_discord_calls([ history_raw(content: "joined", id: "30", type: 7),
                           history_raw(content: "<@BOT> question", id: "20"),
                           history_raw(content: "my answer", id: "10", author_id: "BOT") ])

      assert_empty @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)
    end

    should "return an empty array when the channel has no recent messages" do
      stub_discord_calls([])

      assert_empty @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)
    end

    should "raise when the channel history call fails" do
      Net::HTTP.any_instance.stubs(:request).returns(http_response(403, { "message" => "Missing Access" }))

      assert_raises(DiscordRequestError) do
        @adapter.fetch_channel_history(channel_id: "C1", before: "900", since: @since, limit: 20)
      end
    end
  end

  context "history filtering" do
    should "skip system messages" do
      stub_discord_calls([ history_raw(content: "joined the thread", type: 7) ])

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")
    end

    should "skip the gateway's own messages" do
      stub_discord_calls([ history_raw(content: "my own answer", author_id: "BOT") ])

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")
    end

    should "skip questions addressed to the bot in both mention notations" do
      stub_discord_calls([ history_raw(content: "<@BOT> question", id: "20"),
                           history_raw(content: "<@!BOT> another question", id: "10") ])

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")
    end

    should "skip messages whose content is empty" do
      stub_discord_calls([ history_raw(content: "   ") ])

      assert_empty @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")
    end

    should "import other bots as ordinary participants" do
      raw = history_raw(content: "build failed", username: "CI notifier")
      raw["author"]["bot"] = true
      stub_discord_calls([ raw ])

      history = @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1")

      assert_equal [ "CI notifier" ], history.map(&:speaker)
    end
  end

  context "history speaker names" do
    should "prefer the guild nickname" do
      stub_discord_calls([ history_raw(content: "hello", nick: "yamachan",
                                       global_name: "Yamada Taro", username: "yamada") ])

      assert_equal [ "yamachan" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1").map(&:speaker)
    end

    should "fall back to the global name without a nickname" do
      stub_discord_calls([ history_raw(content: "hello", global_name: "Yamada Taro", username: "yamada") ])

      assert_equal [ "Yamada Taro" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1").map(&:speaker)
    end

    should "fall back to the account name" do
      stub_discord_calls([ history_raw(content: "hello", username: "yamada") ])

      assert_equal [ "yamada" ],
                   @adapter.fetch_thread_history(channel_id: "C1", thread_key: "C1:T1").map(&:speaker)
    end
  end
end
