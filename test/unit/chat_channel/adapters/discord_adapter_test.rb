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

    should "log a debug message and fall back to 1 second when the 429 body cannot be parsed" do
      response = http_response(429, {})
      response.stubs(:body).returns("not json")
      logger = mock("logger")
      logger.expects(:debug).with(regexp_matches(/retry_after/))
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
      @adapter.stubs(:heartbeat_loop)
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
      @adapter.stubs(:heartbeat_loop).with { @adapter.send(:handle_close_frame, 4004); true }
      ws = mock("ws")
      ws.stubs(:on)
      ws.stubs(:close)
      WebSocket::Client::Simple.stubs(:connect).returns(ws)

      assert_raises(DiscordApiError) { @adapter.start }
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

      @adapter.handle_gateway_message({ op: DiscordAdapter::OP_HELLO, d: { heartbeat_interval: 41250 } }.to_json)

      assert_in_delta 41.25, @adapter.instance_variable_get(:@heartbeat_interval), 0.001
    end

    should "mark connected and reset the backoff on READY" do
      3.times { @adapter.send(:next_backoff) }

      @adapter.handle_gateway_message({ op: DiscordAdapter::OP_DISPATCH, t: "READY", s: 1, d: { "user" => { "id" => "B1" } } }.to_json)

      assert_predicate @adapter, :connected?
      assert_equal 1, @adapter.send(:next_backoff)
    end

    should "reply to a server heartbeat request immediately with the last sequence" do
      ws = mock("ws")
      ws.expects(:send).with { |raw| JSON.parse(raw) == { "op" => DiscordAdapter::OP_HEARTBEAT, "d" => 7 } }
      @adapter.instance_variable_set(:@ws, ws)
      @adapter.instance_variable_set(:@last_sequence, 7)

      @adapter.handle_gateway_message({ op: DiscordAdapter::OP_HEARTBEAT }.to_json)
    end

    should "record a heartbeat ack" do
      @adapter.instance_variable_set(:@heartbeat_acked, false)

      @adapter.handle_gateway_message({ op: DiscordAdapter::OP_HEARTBEAT_ACK }.to_json)

      assert @adapter.instance_variable_get(:@heartbeat_acked)
    end

    should "request a reconnect on Reconnect (op 7) and Invalid Session (op 9)" do
      [ DiscordAdapter::OP_RECONNECT, DiscordAdapter::OP_INVALID_SESSION ].each do |op|
        adapter = DiscordAdapter.new
        adapter.instance_variable_set(:@connection_ended, Queue.new)

        adapter.handle_gateway_message({ op: op }.to_json)

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

    should "request a reconnect when a heartbeat ack is missing at the next send time (zombie connection)" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)
      @adapter.instance_variable_set(:@heartbeat_interval, 0.01)
      @adapter.instance_variable_set(:@heartbeat_acked, false)
      @adapter.stubs(:send_heartbeat)

      @adapter.send(:heartbeat_loop)

      assert @adapter.instance_variable_get(:@reconnect_requested)
    end

    should "not capture a fatal error on a transient close code" do
      @adapter.instance_variable_set(:@connection_ended, Queue.new)

      @adapter.handle_close_frame(1006)

      assert_nil @adapter.instance_variable_get(:@fatal_close)
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

  context "history retrieval" do
    should "declare history support" do
      assert_predicate @adapter, :supports_history?
    end

    should "keep the gateway intents unchanged so existing installations still connect" do
      assert_equal 4608, DiscordAdapter::GATEWAY_INTENTS
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
