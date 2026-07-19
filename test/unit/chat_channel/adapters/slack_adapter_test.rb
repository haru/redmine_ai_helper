# frozen_string_literal: true

require File.expand_path("../../../../test_helper", __FILE__)

class ChatChannelSlackAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  setup do
    AiHelperChatAdapterSetting.delete_all
    create(:ai_helper_chat_adapter_setting,
           channel_type: "slack", enabled: true,
           app_token: "xapp-secret", bot_token: "xoxb-secret")
    @adapter = RedmineAiHelper::ChatChannel::Adapters::SlackAdapter.new
  end

  def stub_api_response(body)
    stub(body: body.to_json)
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
      @adapter.stubs(:sleep) { |seconds| slept << seconds }
      call_count = 0
      @adapter.stubs(:listen) do
        call_count += 1
        @adapter.stop if call_count == 2
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
      assert_equal "open issues?", message.text
      assert_equal "U123", message.external_user_id
      assert_not message.dm?
    end

    should "use thread_ts for the thread_key when present" do
      @ws.stubs(:send)

      @adapter.handle_envelope(events_envelope(
        { "type" => "app_mention", "user" => "U123", "channel" => "C123",
          "ts" => "333.444", "thread_ts" => "111.222", "text" => "<@B001> more" }
      ))

      assert_equal "C123:111.222", @dispatcher.messages.first.thread_key
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

  context "web api operations" do
    should "resolve the user email via users.info" do
      @adapter.expects(:api_call).with("users.info", token: "xoxb-secret", params: { user: "U123" })
              .returns({ "ok" => true, "user" => { "profile" => { "email" => "jsmith@somenet.foo" } } })

      assert_equal "jsmith@somenet.foo", @adapter.resolve_user_email(external_user_id: "U123")
    end

    should "return nil when the profile has no email" do
      @adapter.expects(:api_call).with("users.info", token: "xoxb-secret", params: { user: "U123" })
              .returns({ "ok" => true, "user" => { "profile" => {} } })

      assert_nil @adapter.resolve_user_email(external_user_id: "U123")
    end

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

    should "add an hourglass reaction as the processing notice" do
      @adapter.expects(:api_call).with(
        "reactions.add",
        token: "xoxb-secret",
        params: { channel: "C123", timestamp: "111.222", name: "hourglass_flowing_sand" }
      ).returns({ "ok" => true })

      message = RedmineAiHelper::ChatChannel::IncomingMessage.new(
        channel_type: "slack", channel_id: "C123", thread_key: "C123:111.222",
        text: "q", external_user_id: "U123", dm: false
      )
      @adapter.notify_processing(message: message)
    end
  end
end
