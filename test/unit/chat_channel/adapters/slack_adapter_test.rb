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

    should "request a reconnect after two missed pongs" do
      assert_not @adapter.send(:ping_tick)
      assert_not @adapter.send(:ping_tick)
      assert @adapter.send(:ping_tick)
    end

    should "reset missed pongs when a pong arrives" do
      @adapter.send(:ping_tick)
      @adapter.send(:handle_pong)
      assert_not @adapter.send(:ping_tick)
      assert_not @adapter.send(:ping_tick)
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
      @ws.expects(:send).with({ envelope_id: "env-42" }.to_json)

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
end
