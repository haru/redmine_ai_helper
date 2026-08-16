# frozen_string_literal: true

require File.expand_path("../../../../test_helper", __FILE__)

class ChatChannelTeamsAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  TeamsAdapter = RedmineAiHelper::ChatChannel::Adapters::TeamsAdapter

  APP_ID = "11111111-1111-1111-1111-111111111111"
  CLIENT_SECRET = "teams-client-secret"
  TENANT_ID = "22222222-2222-2222-2222-222222222222"
  SERVICE_URL = "https://smba.trafficmanager.net/amer/"
  TEAM_ID = "19:team-general@thread.tacv2"
  CHANNEL_ID = "19:channel-general@thread.tacv2"
  ROOT_MESSAGE_ID = "1700000000000"
  CONVERSATION_ID = "#{CHANNEL_ID};messageid=#{ROOT_MESSAGE_ID}"
  PERSONAL_CONVERSATION_ID = "a:1abcdefg"
  BOT_ID = "28:#{APP_ID}"
  ISSUER = "https://api.botframework.com"
  JWKS_URI = "https://login.botframework.com/v1/.well-known/keys"
  AAD_GROUP_ID = "33333333-3333-3333-3333-333333333333"
  GRAPH_CHANNEL_URL = "https://graph.microsoft.com/v1.0/teams/#{AAD_GROUP_ID}/channels/#{CHANNEL_ID}"

  # One key pair for the whole suite: generating an RSA key is expensive and
  # every signing test only needs "the key the JWKS endpoint hands out".
  SIGNING_KEY = OpenSSL::PKey::RSA.generate(2048)
  SIGNING_KID = "teams-test-key"

  setup do
    AiHelperChatAdapterSetting.delete_all
    AiHelperInboundEvent.delete_all
    create(:ai_helper_chat_adapter_setting,
           channel_type: "teams", enabled: true, app_token: APP_ID, bot_token: CLIENT_SECRET,
           tenant_id: TENANT_ID, redmine_user_id: 2, default_project_id: 1)
    # The signing keys are cached on the class and therefore outlive one
    # test: every assertion about how often they are read starts from empty.
    TeamsAdapter.reset_jwks_cache
    @adapter = TeamsAdapter.new
  end

  # Stand-in for Net::HTTPResponse: only the status code, the body and the
  # headers the adapter reads are needed.
  class FakeResponse
    # @return [String] the HTTP status code
    attr_reader :code
    # @return [String] the raw response body
    attr_reader :body

    def initialize(code, body, headers)
      @code = code.to_s
      @body = body
      @headers = headers
    end

    delegate :[], to: :@headers
  end

  def http_response(code, body = {}, headers = {})
    FakeResponse.new(code, body.is_a?(String) ? body : body.to_json, headers)
  end

  # Answers every HTTP call the adapter makes with the queued responses in
  # order (the last one repeats), recording the URI it built and the request
  # it sent so both can be asserted.
  def stub_http(*responses)
    @http_uris = []
    @http_requests = []
    # Recording happens in the matcher block, which mocha also runs for every
    # earlier stub of the same method: without this a second stub_http in one
    # test would record each call twice.
    Net::HTTP.any_instance.unstub(:request)
    @adapter.stubs(:build_http).with { |uri| @http_uris << uri; true }
            .returns(Net::HTTP.new("stubbed.invalid", 443))
    Net::HTTP.any_instance.stubs(:request).with { |request| @http_requests << request; true }
             .returns(*responses)
  end

  def token_response(token: "access-token", expires_in: 3600)
    http_response(200, { "access_token" => token, "expires_in" => expires_in })
  end

  def form_data(index)
    URI.decode_www_form(@http_requests[index].body.to_s).to_h
  end

  def jwks_body(kid: SIGNING_KID)
    { "keys" => [ JWT::JWK.new(SIGNING_KEY, kid: kid).export ] }
  end

  # Answers the OpenID metadata and JWKS calls, plus any further calls with
  # the given responses.
  def stub_jwks(*responses, kid: SIGNING_KID)
    stub_http(http_response(200, { "issuer" => ISSUER, "jwks_uri" => JWKS_URI }),
              http_response(200, jwks_body(kid: kid)), *responses)
  end

  def bot_token(claims = {}, key: SIGNING_KEY, algorithm: "RS256", kid: SIGNING_KID)
    payload = {
      "iss" => ISSUER, "aud" => APP_ID, "serviceUrl" => SERVICE_URL,
      "nbf" => Time.now.to_i - 10, "exp" => Time.now.to_i + 600
    }.merge(claims)
    JWT.encode(payload, key, algorithm, { "kid" => kid })
  end

  # A real ActionDispatch::Request, the way the webhook controller hands one
  # to the adapter.
  def teams_request(activity, token: bot_token)
    body = activity.is_a?(String) ? activity : activity.to_json
    env = Rack::MockRequest.env_for("/ai_helper/chat_webhook/teams", method: "POST", input: body,
                                    "CONTENT_TYPE" => "application/json")
    env["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    ActionDispatch::Request.new(env)
  end

  # Stores an event the way the webhook endpoint does, so the adapter can
  # resolve the reply destination of the conversation being answered.
  def stored_event(thread_key: CONVERSATION_ID, channel_id: CHANNEL_ID, message_ts: ROOT_MESSAGE_ID,
                   received_at: Time.current, metadata: { service_url: SERVICE_URL,
                                                          conversation_id: CONVERSATION_ID,
                                                          team_id: TEAM_ID })
    AiHelperInboundEvent.create!(
      channel_type: "teams", event_key: "#{thread_key}:#{message_ts}", text: "question",
      channel_id: channel_id, thread_key: thread_key, message_ts: message_ts,
      received_at: received_at, reply_metadata: metadata
    )
  end

  # Posts a reply as if the gateway were answering the given stored event.
  def send_reply(event, text, thread_key: CONVERSATION_ID)
    @adapter.answering(event.id) do
      @adapter.send_message(channel_id: CHANNEL_ID, thread_key: thread_key, text: text)
    end
  end

  # The JSON bodies of every call after the initial token request.
  def posted_bodies
    @http_requests.drop(1).map { |request| JSON.parse(request.body) }
  end

  # Answers the calls every history retrieval starts with (a Bot Connector
  # token, the team lookup that resolves the group id, and a Graph token)
  # before the queued Graph responses.
  def stub_history(*responses)
    stub_http(token_response, http_response(200, { "aadGroupId" => AAD_GROUP_ID }),
              token_response(token: "graph-token"), *responses)
  end

  # The channel history the adapter builds from the given raw Graph messages.
  def imported(*messages)
    stub_history(http_response(200, { "value" => messages }))
    @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                   since: 48.hours.ago, limit: 20)
  end

  # The Graph URLs called after the token and team lookups.
  def graph_uris
    @http_uris.drop(3).map(&:to_s)
  end

  # +created+ defaults to a moment inside the window #imported asks for. A
  # fixed date would leave that window as the days pass and drop every message
  # before the conversion under test ever ran.
  def graph_message(id:, text: "a message", speaker: "Taro Yamada", content_type: "text",
                    message_type: "message", created: 1.hour.ago.utc.iso8601, from: nil,
                    mentions: nil)
    message = {
      "id" => id, "messageType" => message_type, "createdDateTime" => created,
      "from" => from || { "user" => { "displayName" => speaker } },
      "body" => { "contentType" => content_type, "content" => text }
    }
    message["mentions"] = mentions if mentions
    message
  end

  def channel_activity(overrides = {})
    {
      "type" => "message", "id" => ROOT_MESSAGE_ID, "serviceUrl" => SERVICE_URL,
      "from" => { "id" => "29:speaker", "name" => "Taro Yamada", "aadObjectId" => "aad-object-id" },
      "recipient" => { "id" => BOT_ID },
      "conversation" => { "id" => CONVERSATION_ID, "conversationType" => "channel" },
      "channelData" => {
        "tenant" => { "id" => TENANT_ID }, "team" => { "id" => TEAM_ID },
        "channel" => { "id" => CHANNEL_ID }
      },
      "text" => "<at>AI Helper</at> what is still open?",
      "entities" => [ {
        "type" => "mention", "text" => "<at>AI Helper</at>",
        "mentioned" => { "id" => BOT_ID, "name" => "AI Helper" }
      } ]
    }.deep_merge(overrides)
  end

  def personal_activity(overrides = {})
    {
      "type" => "message", "id" => "1700000000500", "serviceUrl" => SERVICE_URL,
      "from" => { "id" => "29:speaker", "name" => "Taro Yamada" },
      "recipient" => { "id" => BOT_ID },
      "conversation" => { "id" => PERSONAL_CONVERSATION_ID, "conversationType" => "personal",
                          "tenantId" => TENANT_ID },
      "text" => "  what is still open?  "
    }.deep_merge(overrides)
  end

  context "declaration" do
    should "identify itself as the teams adapter" do
      assert_equal "teams", TeamsAdapter.channel_type
    end

    should "require the app id, the client secret and the tenant id" do
      assert_equal [ :app_token, :bot_token, :tenant_id ], TeamsAdapter.required_setting_fields
    end

    should "be an inbound adapter" do
      assert TeamsAdapter.inbound?
    end
  end

  context "#issue_link_format" do
    should "render issue references as markdown links" do
      format = @adapter.issue_link_format

      assert_equal "[#1](https://example.com/issues/1)",
                   format.render("#1", "https://example.com/issues/1")
    end

    should "detect its own rendered links" do
      format = @adapter.issue_link_format

      assert_match format.pattern, "see [#1](https://example.com/issues/1) for details"
    end
  end

  context "access tokens" do
    # The bot is a single-tenant app, so its credentials only exist in the
    # configured directory: the fixed botframework.com endpoint is for
    # multi-tenant bots and rejects them.
    should "request a Bot Connector token from the tenant endpoint" do
      stub_http(token_response(token: "connector-token"))

      assert_equal "connector-token", @adapter.send(:access_token, :connector)
      assert_equal "login.microsoftonline.com", @http_uris.first.host
      assert_equal "/#{TENANT_ID}/oauth2/v2.0/token", @http_uris.first.path
      assert_equal({ "grant_type" => "client_credentials", "client_id" => APP_ID,
                     "client_secret" => CLIENT_SECRET,
                     "scope" => "https://api.botframework.com/.default" },
                   form_data(0))
    end

    should "request a Graph token from the tenant endpoint" do
      stub_http(token_response(token: "graph-token"))

      assert_equal "graph-token", @adapter.send(:access_token, :graph)
      assert_equal "/#{TENANT_ID}/oauth2/v2.0/token", @http_uris.first.path
      assert_equal "https://graph.microsoft.com/.default", form_data(0)["scope"]
    end

    should "cache each scope's token separately" do
      stub_http(token_response(token: "connector-token"), token_response(token: "graph-token"))

      assert_equal "connector-token", @adapter.send(:access_token, :connector)
      assert_equal "graph-token", @adapter.send(:access_token, :graph)
      assert_equal "connector-token", @adapter.send(:access_token, :connector)
      assert_equal 2, @http_requests.size
    end

    should "reuse a cached token while it is valid" do
      stub_http(token_response(token: "first"), token_response(token: "second"))

      3.times { @adapter.send(:access_token, :connector) }

      assert_equal 1, @http_requests.size
    end

    should "fetch a new token once less than 60 seconds of lifetime remain" do
      stub_http(token_response(token: "first", expires_in: 30), token_response(token: "second"))

      assert_equal "first", @adapter.send(:access_token, :connector)

      assert_equal "second", @adapter.send(:access_token, :connector)
      assert_equal 2, @http_requests.size
    end

    should "raise a fatal error when the token endpoint rejects the credentials" do
      [ 400, 401 ].each do |code|
        @adapter = TeamsAdapter.new
        stub_http(http_response(code, { "error" => "invalid_client" }))

        error = assert_raises(TeamsAdapter::TeamsApiError) { @adapter.send(:access_token, :connector) }

        assert @adapter.fatal_config_error?(error)
      end
    end

    should "raise a retryable error when the token endpoint fails for another reason" do
      stub_http(http_response(503, { "error" => "unavailable" }))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { @adapter.send(:access_token, :graph) }

      assert_equal 503, error.status
    end

    # Caching a nil token would send an empty Authorization header, and the
    # 401 that follows would be reported as "your credentials are wrong".
    should "raise when an accepted token response carries no token" do
      stub_http(http_response(200, { "expires_in" => 3600 }))

      assert_raises(TeamsAdapter::TeamsRequestError) { @adapter.send(:access_token, :connector) }
    end

    # #mentions_bot? asks for the app id once per imported message and
    # #verify_request asks for it and for the tenant on every delivery: an
    # unmemoized read puts one SELECT behind each of those.
    should "read each settings value once however often it is used" do
      @adapter.expects(:settings).twice.returns(AiHelperChatAdapterSetting.for_channel("teams"))

      3.times { assert_equal APP_ID, @adapter.send(:app_id) }
      3.times { assert_equal TENANT_ID, @adapter.send(:configured_tenant_id) }
    end

    should "never disclose credentials in an access token error message" do
      stub_http(http_response(401, { "error_description" => "AADSTS7000215: Invalid client secret #{CLIENT_SECRET}" }))

      error = assert_raises(TeamsAdapter::TeamsApiError) { @adapter.send(:access_token, :connector) }

      assert_not_includes error.message, APP_ID
      assert_not_includes error.message, CLIENT_SECRET
    end
  end

  context "#verify_request" do
    should "accept a correctly signed activity from the allowed tenant" do
      stub_jwks

      assert @adapter.verify_request(teams_request(channel_activity))
    end

    should "read the signing keys through the Bot Framework OpenID metadata" do
      stub_jwks

      @adapter.verify_request(teams_request(channel_activity))

      assert_equal "https://login.botframework.com/v1/.well-known/openidconfiguration",
                   @http_uris.first.to_s
      assert_equal JWKS_URI, @http_uris.second.to_s
    end

    should "accept an activity whose tenant is only named by the conversation" do
      stub_jwks
      activity = channel_activity.merge(
        "channelData" => { "team" => { "id" => TEAM_ID }, "channel" => { "id" => CHANNEL_ID } }
      )
      activity["conversation"] = activity["conversation"].merge("tenantId" => TENANT_ID)

      assert @adapter.verify_request(teams_request(activity))
    end

    should "reuse the cached signing keys across requests" do
      stub_jwks

      3.times { @adapter.verify_request(teams_request(channel_activity)) }

      assert_equal 2, @http_requests.size
    end

    should "refetch the signing keys once when the key id is unknown" do
      stub_http(http_response(200, { "jwks_uri" => JWKS_URI }),
                http_response(200, jwks_body(kid: "rotated-away")),
                http_response(200, { "jwks_uri" => JWKS_URI }),
                http_response(200, jwks_body))

      assert @adapter.verify_request(teams_request(channel_activity))
      assert_equal 4, @http_requests.size
    end

    should "refetch the signing keys once the cache is a day old" do
      stub_jwks(http_response(200, { "jwks_uri" => JWKS_URI }), http_response(200, jwks_body))
      @adapter.verify_request(teams_request(channel_activity))
      TeamsAdapter.instance_variable_set(:@jwks_fetched_at,
                                         TeamsAdapter.monotonic_now - (24 * 60 * 60) - 1)

      assert @adapter.verify_request(teams_request(channel_activity))
      assert_equal 4, @http_requests.size
    end

    # The webhook endpoint builds a new adapter for every delivery, so keys
    # cached on the instance would be read again on every single request.
    should "read the signing keys once for the process, not once per delivery" do
      stub_jwks
      next_delivery = TeamsAdapter.new
      next_delivery.stubs(:build_http).returns(Net::HTTP.new("stubbed.invalid", 443))

      assert @adapter.verify_request(teams_request(channel_activity))
      assert next_delivery.verify_request(teams_request(channel_activity))
      assert_equal 2, @http_requests.size
    end

    should "raise rather than refuse when the signing keys cannot be read" do
      stub_http(http_response(500, { "error" => "unavailable" }))

      assert_raises(TeamsAdapter::TeamsRequestError) do
        @adapter.verify_request(teams_request(channel_activity))
      end
    end
  end

  context "#verify_request refusals" do
    should "refuse a request without a bearer token" do
      stub_jwks

      assert_not @adapter.verify_request(teams_request(channel_activity, token: nil))
      assert_empty @http_requests
    end

    should "refuse a token sent with another scheme" do
      stub_jwks
      request = teams_request(channel_activity)
      request.set_header("HTTP_AUTHORIZATION", "Basic #{bot_token}")

      assert_not @adapter.verify_request(request)
    end

    should "refuse a token signed by another key" do
      stub_jwks
      other_key = OpenSSL::PKey::RSA.generate(2048)

      assert_not @adapter.verify_request(teams_request(channel_activity, token: bot_token(key: other_key)))
    end

    should "refuse a token issued for another audience" do
      stub_jwks

      assert_not @adapter.verify_request(
        teams_request(channel_activity, token: bot_token({ "aud" => "another-app-id" }))
      )
    end

    should "refuse a token from another issuer" do
      stub_jwks

      assert_not @adapter.verify_request(
        teams_request(channel_activity, token: bot_token({ "iss" => "https://evil.example.com" }))
      )
    end

    should "refuse an expired token" do
      stub_jwks

      assert_not @adapter.verify_request(
        teams_request(channel_activity, token: bot_token({ "exp" => Time.now.to_i - 400 }))
      )
    end

    should "refuse a token that is not valid yet" do
      stub_jwks

      assert_not @adapter.verify_request(
        teams_request(channel_activity, token: bot_token({ "nbf" => Time.now.to_i + 400 }))
      )
    end

    should "refuse a token signed with another algorithm" do
      stub_jwks
      token = JWT.encode({ "iss" => ISSUER, "aud" => APP_ID, "serviceUrl" => SERVICE_URL,
                           "exp" => Time.now.to_i + 600 }, "shared-secret", "HS256",
                         { "kid" => SIGNING_KID })

      assert_not @adapter.verify_request(teams_request(channel_activity, token: token))
    end

    should "refuse a token that carries no serviceUrl claim" do
      stub_jwks
      token = JWT.encode({ "iss" => ISSUER, "aud" => APP_ID, "exp" => Time.now.to_i + 600 },
                         SIGNING_KEY, "RS256", { "kid" => SIGNING_KID })

      assert_not @adapter.verify_request(teams_request(channel_activity, token: token))
    end

    should "refuse a serviceUrl claim that does not match the activity" do
      stub_jwks

      assert_not @adapter.verify_request(
        teams_request(channel_activity, token: bot_token({ "serviceUrl" => "https://elsewhere.example.com/" }))
      )
    end

    should "refuse a body that cannot be parsed" do
      stub_jwks

      assert_not @adapter.verify_request(teams_request("{not json"))
      assert_not @adapter.verify_request(teams_request("[]"))
    end

    should "refuse an activity from another organization" do
      stub_jwks
      activity = channel_activity("channelData" => { "tenant" => { "id" => "99999999-9999-9999-9999-999999999999" } })

      assert_not @adapter.verify_request(teams_request(activity))
    end

    # The tenant comparison is the only gate between a genuinely signed
    # request from another organization and the queue, so it must not turn
    # into "everything passes" when the setting is missing.
    should "refuse an activity naming no tenant when none is configured either" do
      stub_jwks
      @adapter.stubs(:settings)
              .returns(AiHelperChatAdapterSetting.new(channel_type: "teams", app_token: APP_ID))
      activity = channel_activity
      activity["channelData"] = activity["channelData"].except("tenant")
      activity["conversation"] = activity["conversation"].except("tenantId")

      assert_not @adapter.verify_request(teams_request(activity))
    end

    should "log the reason for a refusal without disclosing any credential" do
      stub_jwks
      logged = []
      logger = stub("logger")
      logger.stubs(:warn).with { |message| logged << message; true }
      logger.stubs(:debug)
      logger.stubs(:info)
      @adapter.stubs(:ai_helper_logger).returns(logger)
      activity = channel_activity("channelData" => { "tenant" => { "id" => "99999999-9999-9999-9999-999999999999" } })

      @adapter.verify_request(teams_request(activity))

      assert_match(/tenant/, logged.join("\n"))
      assert_not_includes logged.join("\n"), CLIENT_SECRET
      assert_not_includes logged.join("\n"), bot_token
    end
  end

  context "#parse_events in a team channel" do
    should "normalize a mention into one event" do
      events = @adapter.parse_events(teams_request(channel_activity))

      assert_equal 1, events.size
      assert_equal({ event_key: "#{CONVERSATION_ID}:#{ROOT_MESSAGE_ID}",
                     text: "what is still open?", channel_id: CHANNEL_ID,
                     thread_key: CONVERSATION_ID, message_ts: ROOT_MESSAGE_ID,
                     dm: false, in_thread: false,
                     reply_metadata: { service_url: SERVICE_URL, conversation_id: CONVERSATION_ID,
                                       team_id: TEAM_ID } },
                   events.first)
    end

    should "mark a reply inside an existing thread as in_thread" do
      events = @adapter.parse_events(teams_request(channel_activity("id" => "1700000009999")))

      assert events.first[:in_thread]
      assert_equal "#{CONVERSATION_ID}:1700000009999", events.first[:event_key]
      assert_equal CONVERSATION_ID, events.first[:thread_key]
    end

    should "carry no speaker identity into the stored event" do
      events = @adapter.parse_events(teams_request(channel_activity))
      serialized = events.first.to_json

      assert_not_includes serialized, "29:speaker"
      assert_not_includes serialized, "Taro Yamada"
      assert_not_includes serialized, "aad-object-id"
    end

    should "remove only the mention of the bot itself" do
      activity = channel_activity(
        "text" => "<at>AI Helper</at> ask <at>Taro Yamada</at> about the release",
        "entities" => [
          { "type" => "mention", "text" => "<at>AI Helper</at>", "mentioned" => { "id" => BOT_ID } },
          { "type" => "mention", "text" => "<at>Taro Yamada</at>", "mentioned" => { "id" => "29:speaker" } }
        ]
      )

      events = @adapter.parse_events(teams_request(activity))

      assert_equal "ask <at>Taro Yamada</at> about the release", events.first[:text]
    end
  end

  context "#parse_events in a one-to-one chat" do
    should "normalize a message without a mention into one event" do
      events = @adapter.parse_events(teams_request(personal_activity))

      assert_equal 1, events.size
      event = events.first
      assert_equal "what is still open?", event[:text]
      assert_equal PERSONAL_CONVERSATION_ID, event[:channel_id]
      assert_equal "#{PERSONAL_CONVERSATION_ID}:1700000000500", event[:event_key]
      assert_equal "1700000000500", event[:message_ts]
      assert event[:dm]
      assert_not event[:in_thread]
      assert_match(/\A#{Regexp.escape(PERSONAL_CONVERSATION_ID)}\#s=\d+\z/, event[:thread_key])
      assert_equal({ service_url: SERVICE_URL, conversation_id: PERSONAL_CONVERSATION_ID },
                   event[:reply_metadata])
    end

    should "continue the session of a recent message" do
      existing = stored_event(thread_key: "#{PERSONAL_CONVERSATION_ID}\#s=1700000000",
                              channel_id: PERSONAL_CONVERSATION_ID, message_ts: "1700000000100",
                              received_at: 23.hours.ago)

      events = @adapter.parse_events(teams_request(personal_activity))

      assert_equal existing.thread_key, events.first[:thread_key]
    end

    should "start a new session once 24 hours have passed" do
      existing = stored_event(thread_key: "#{PERSONAL_CONVERSATION_ID}\#s=1700000000",
                              channel_id: PERSONAL_CONVERSATION_ID, message_ts: "1700000000100",
                              received_at: 25.hours.ago)

      events = @adapter.parse_events(teams_request(personal_activity))

      assert_not_equal existing.thread_key, events.first[:thread_key]
      assert_match(/\A#{Regexp.escape(PERSONAL_CONVERSATION_ID)}\#s=\d+\z/, events.first[:thread_key])
    end

    should "not continue the session of another conversation" do
      stored_event(thread_key: CONVERSATION_ID, channel_id: CHANNEL_ID, received_at: 1.minute.ago)

      events = @adapter.parse_events(teams_request(personal_activity))

      assert_not_equal CONVERSATION_ID, events.first[:thread_key]
    end

    should "only read the stored events, never write one" do
      assert_no_difference "AiHelperInboundEvent.count" do
        @adapter.parse_events(teams_request(personal_activity))
      end
    end

    should "ignore a message with no text at all" do
      assert_empty @adapter.parse_events(teams_request(personal_activity("text" => "   ")))
    end
  end

  context "history retrieval" do
    setup do
      stored_event
    end

    should "declare that it can retrieve past messages" do
      assert @adapter.supports_history?
    end

    should "retrieve nothing at all for a one-to-one chat" do
      stub_http
      stored_event(thread_key: "#{PERSONAL_CONVERSATION_ID}\#s=1700000000",
                   channel_id: PERSONAL_CONVERSATION_ID, message_ts: "1700000000100")

      assert_empty @adapter.fetch_thread_history(channel_id: PERSONAL_CONVERSATION_ID,
                                                 thread_key: "#{PERSONAL_CONVERSATION_ID}\#s=1700000000")
      assert_empty @adapter.fetch_channel_history(channel_id: PERSONAL_CONVERSATION_ID,
                                                  before: "1700000000100", since: 48.hours.ago, limit: 20)
      assert_empty @http_requests
    end

    should "resolve the team's group id once and reuse it" do
      stub_history(http_response(200, { "value" => [] }), http_response(200, { "value" => [] }))

      2.times do
        @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                       since: 48.hours.ago, limit: 20)
      end

      team_lookups = @http_uris.map(&:to_s).select { |uri| uri.include?("v3/teams/") }
      assert_equal [ "#{SERVICE_URL}v3/teams/#{TEAM_ID}" ], team_lookups
    end

    should "keep at most 100 resolved group ids, dropping the oldest first" do
      101.times { |index| @adapter.send(:remember_aad_group_id, "team-#{index}", "group-#{index}") }
      cache = @adapter.instance_variable_get(:@aad_group_ids)

      assert_equal 100, cache.size
      assert_nil cache["team-0"]
      assert_equal "group-100", cache["team-100"]
    end
  end

  context "#fetch_thread_history" do
    setup do
      stored_event
    end

    should "read the root message and every reply of the thread" do
      stub_history(
        http_response(200, graph_message(id: ROOT_MESSAGE_ID, text: "the root question")),
        http_response(200, { "value" => [ graph_message(id: "1700000000100", text: "first reply") ],
                             "@odata.nextLink" => "#{GRAPH_CHANNEL_URL}/messages/#{ROOT_MESSAGE_ID}/replies?$skiptoken=x" }),
        http_response(200, { "value" => [ graph_message(id: "1700000000200", text: "second reply") ] })
      )

      history = @adapter.fetch_thread_history(channel_id: CHANNEL_ID, thread_key: CONVERSATION_ID)

      assert_equal [ "the root question", "first reply", "second reply" ], history.map(&:text)
      assert_equal [ "#{GRAPH_CHANNEL_URL}/messages/#{ROOT_MESSAGE_ID}",
                     "#{GRAPH_CHANNEL_URL}/messages/#{ROOT_MESSAGE_ID}/replies?$top=50",
                     "#{GRAPH_CHANNEL_URL}/messages/#{ROOT_MESSAGE_ID}/replies?$skiptoken=x" ],
                   graph_uris
    end

    should "return only the replies after the import cursor" do
      stub_history(http_response(200, { "value" => [
        graph_message(id: "1700000000300", text: "newer"),
        graph_message(id: "1700000000100", text: "older")
      ] }))

      history = @adapter.fetch_thread_history(channel_id: CHANNEL_ID, thread_key: CONVERSATION_ID,
                                              after: "1700000000200")

      assert_equal [ "newer" ], history.map(&:text)
      assert_equal [ "#{GRAPH_CHANNEL_URL}/messages/#{ROOT_MESSAGE_ID}/replies?$top=50" ], graph_uris
    end

    should "raise when the conversation id does not name the thread's root message" do
      assert_raises(ArgumentError) do
        @adapter.fetch_thread_history(channel_id: CHANNEL_ID, thread_key: CHANNEL_ID)
      end
    end

    should "return the replies oldest first" do
      stub_history(http_response(200, { "value" => [
        graph_message(id: "1700000000300", text: "third"),
        graph_message(id: "1700000000100", text: "first"),
        graph_message(id: "1700000000200", text: "second")
      ] }))

      history = @adapter.fetch_thread_history(channel_id: CHANNEL_ID, thread_key: CONVERSATION_ID,
                                              after: "1700000000000")

      assert_equal [ "first", "second", "third" ], history.map(&:text)
    end
  end

  context "#fetch_channel_history" do
    setup do
      stored_event
    end

    should "read one page of the channel's messages" do
      stub_history(http_response(200, { "value" => [ graph_message(id: "1700000000100") ] }))

      @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                     since: 48.hours.ago, limit: 20)

      assert_equal [ "#{GRAPH_CHANNEL_URL}/messages?$top=20" ], graph_uris
    end

    should "keep only the messages before the mention and inside the lookback window" do
      stub_history(http_response(200, { "value" => [
        graph_message(id: "1700000000300", text: "recent", created: 1.hour.ago.utc.iso8601),
        graph_message(id: "1700000000100", text: "too old", created: 60.hours.ago.utc.iso8601),
        graph_message(id: "1700000009999", text: "the mention itself", created: 1.minute.ago.utc.iso8601)
      ] }))

      history = @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                               since: 48.hours.ago, limit: 20)

      assert_equal [ "recent" ], history.map(&:text)
    end

    should "return the messages oldest first" do
      stub_history(http_response(200, { "value" => [
        graph_message(id: "1700000000300", text: "third", created: 1.hour.ago.utc.iso8601),
        graph_message(id: "1700000000100", text: "first", created: 3.hours.ago.utc.iso8601),
        graph_message(id: "1700000000200", text: "second", created: 2.hours.ago.utc.iso8601)
      ] }))

      history = @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                               since: 48.hours.ago, limit: 20)

      assert_equal [ "first", "second", "third" ], history.map(&:text)
    end
  end

  context "history conversion" do
    setup do
      stored_event
    end

    should "name the speaker with their display name" do
      history = imported(graph_message(id: "1700000000100", text: "hello", speaker: "Hanako Suzuki"))

      assert_equal [ "Hanako Suzuki" ], history.map(&:speaker)
    end

    should "name an unidentifiable speaker instead of leaving it empty" do
      history = imported(graph_message(id: "1700000000100", text: "hello",
                                       from: { "user" => { "id" => "u1" } }))

      assert_equal 1, history.size
      assert_predicate history.first.speaker, :present?
    end

    should "drop the messages posted by an application" do
      history = imported(
        graph_message(id: "1700000000100", text: "from the bot",
                      from: { "application" => { "id" => APP_ID } }),
        graph_message(id: "1700000000200", text: "from a person")
      )

      assert_equal [ "from a person" ], history.map(&:text)
    end

    should "drop the messages without an identified sender" do
      history = imported(graph_message(id: "1700000000100", text: "orphan", from: {}))

      assert_empty history
    end

    should "drop the messages that mention the bot" do
      history = imported(
        graph_message(id: "1700000000100", text: "<at>AI Helper</at> what is open?",
                      mentions: [ { "mentioned" => { "application" => { "id" => APP_ID } } } ]),
        graph_message(id: "1700000000200", text: "unrelated chatter")
      )

      assert_equal [ "unrelated chatter" ], history.map(&:text)
    end

    should "drop everything that is not a plain message" do
      history = imported(graph_message(id: "1700000000100", text: "joined the team",
                                       message_type: "systemEventMessage"))

      assert_empty history
    end

    should "reduce an HTML body to its text" do
      history = imported(graph_message(id: "1700000000100", content_type: "html",
                                       text: "<div><p>ship it &amp; relax</p></div>"))

      assert_equal [ "ship it & relax" ], history.map(&:text)
    end

    should "drop a body that is empty once the markup is removed" do
      history = imported(graph_message(id: "1700000000100", content_type: "html", text: "<div></div>"))

      assert_empty history
    end

    # One unreadable message is dropped like every other unusable one, rather
    # than failing the import of the whole page.
    should "drop a message whose timestamp cannot be read" do
      history = imported(
        graph_message(id: "1700000000100", text: "broken", created: "the other day"),
        graph_message(id: "1700000000200", text: "readable", created: 1.hour.ago.utc.iso8601)
      )

      assert_equal [ "readable" ], history.map(&:text)
    end
  end

  context "history failures" do
    setup do
      stored_event
      @adapter.stubs(:sleep)
    end

    should "raise rather than answer with an empty history" do
      { 403 => TeamsAdapter::TeamsApiError, 404 => TeamsAdapter::TeamsRequestError,
        500 => TeamsAdapter::TeamsRequestError }.each do |code, error_class|
        @adapter = TeamsAdapter.new
        @adapter.stubs(:sleep)
        stub_history(http_response(code, { "error" => { "code" => "Forbidden" } }))

        assert_raises(error_class) do
          @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                         since: 48.hours.ago, limit: 20)
        end
      end
    end

    # A throttled context import must not cost the answer its surrounding
    # messages where repeating the read would have worked.
    should "retry a throttled graph read before giving up" do
      stub_history(http_response(429, {}, { "Retry-After" => "1" }),
                   http_response(200, { "value" => [
                     graph_message(id: "1700000000100", text: "recovered",
                                   created: 1.hour.ago.utc.iso8601)
                   ] }))

      history = @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                               since: 48.hours.ago, limit: 20)

      assert_equal [ "recovered" ], history.map(&:text)
    end

    should "raise when no stored event names the team of the channel" do
      AiHelperInboundEvent.delete_all
      stub_http

      assert_raises(TeamsAdapter::TeamsRequestError) do
        @adapter.fetch_channel_history(channel_id: CHANNEL_ID, before: "1700000009999",
                                       since: 48.hours.ago, limit: 20)
      end
    end
  end

  context "#parse_events refusals" do
    should "ignore an activity that is not a message" do
      assert_empty @adapter.parse_events(teams_request(channel_activity("type" => "conversationUpdate")))
    end

    should "ignore the bot's own message" do
      activity = channel_activity("from" => { "id" => BOT_ID })

      assert_empty @adapter.parse_events(teams_request(activity))
    end

    should "ignore a conversation type this integration does not answer" do
      activity = channel_activity("conversation" => { "conversationType" => "groupChat" })

      assert_empty @adapter.parse_events(teams_request(activity))
    end

    should "ignore a channel message that does not mention the bot" do
      activity = channel_activity("text" => "just chatting", "entities" => [])

      assert_empty @adapter.parse_events(teams_request(activity))
    end

    should "ignore a mention of someone else only" do
      activity = channel_activity(
        "text" => "<at>Taro Yamada</at> any update?",
        "entities" => [ { "type" => "mention", "text" => "<at>Taro Yamada</at>",
                          "mentioned" => { "id" => "29:speaker" } } ]
      )

      assert_empty @adapter.parse_events(teams_request(activity))
    end

    should "ignore a mention with nothing but whitespace left" do
      activity = channel_activity("text" => "<at>AI Helper</at>   ")

      assert_empty @adapter.parse_events(teams_request(activity))
    end

    should "raise on a payload it cannot interpret" do
      assert_raises(JSON::ParserError) { @adapter.parse_events(teams_request("{broken")) }
      assert_raises(ArgumentError) { @adapter.parse_events(teams_request("[]")) }
      assert_raises(ArgumentError) do
        @adapter.parse_events(teams_request(channel_activity.except("serviceUrl")))
      end
      assert_raises(ArgumentError) do
        @adapter.parse_events(teams_request(channel_activity.except("id")))
      end
      assert_raises(ArgumentError) do
        activity = channel_activity
        activity["channelData"] = activity["channelData"].except("channel")
        @adapter.parse_events(teams_request(activity))
      end
    end
  end

  context "#send_message failures" do
    setup do
      @event = stored_event
      @slept = []
      @adapter.stubs(:sleep).with { |seconds| @slept << seconds; true }
    end

    should "give up without retrying when the credentials are refused" do
      [ 401, 403 ].each do |code|
        # A fresh adapter per status: the token cached by the previous pass
        # would otherwise absorb the queued token response.
        @adapter = TeamsAdapter.new
        @slept = []
        @adapter.stubs(:sleep).with { |seconds| @slept << seconds; true }
        stub_http(token_response, http_response(code, { "error" => { "code" => "Unauthorized" } }))

        error = assert_raises(TeamsAdapter::TeamsApiError) { send_reply(@event, "answer") }

        assert @adapter.fatal_config_error?(error)
        assert_equal 2, @http_requests.size
        assert_empty @slept
      end
    end

    should "wait the requested time and retry when it is throttled" do
      stub_http(token_response,
                http_response(429, { "error" => "throttled" }, { "Retry-After" => "2" }),
                http_response(200))

      send_reply(@event, "answer")

      assert_equal [ 2.0 ], @slept
      assert_equal 3, @http_requests.size
    end

    should "give up after three throttled retries" do
      stub_http(token_response, http_response(429, {}, { "Retry-After" => "1" }))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_equal 429, error.status
      assert_equal [ 1.0, 1.0, 1.0 ], @slept
      assert_not @adapter.fatal_config_error?(error)
    end

    # Answers are processed by a single worker, so a Retry-After of several
    # minutes would stop every later question for as long as Teams asks.
    should "wait no longer than a minute however long Teams asks for" do
      stub_http(token_response, http_response(429, {}, { "Retry-After" => "600" }))

      assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_equal [ 60.0, 60.0, 60.0 ], @slept
    end

    should "back off exponentially when Teams fails temporarily" do
      stub_http(token_response, http_response(503))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_equal 503, error.status
      assert_equal [ 1, 2, 4 ], @slept
    end

    should "recover when a temporary failure clears" do
      stub_http(token_response, http_response(500), http_response(200))

      send_reply(@event, "answer")

      assert_equal [ 1 ], @slept
    end

    should "not retry a conversation that no longer exists" do
      stub_http(token_response, http_response(404))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_equal 404, error.status
      assert_empty @slept
    end

    should "not retry any other rejected request" do
      stub_http(token_response, http_response(400))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_equal 400, error.status
      assert_empty @slept
    end

    should "never disclose credentials in a failure message" do
      stub_http(token_response, http_response(400))

      error = assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(@event, "answer") }

      assert_not_includes error.message, CLIENT_SECRET
      assert_not_includes error.message, "access-token"
    end
  end

  context "#send_message" do
    should "post the reply into the conversation the question came from" do
      stub_http(token_response, http_response(200, { "id" => "1700000001111" }))
      event = stored_event

      send_reply(event, "here is the answer")

      assert_equal "#{SERVICE_URL}v3/conversations/#{CONVERSATION_ID}/activities",
                   @http_uris.second.to_s
      assert_equal({ "type" => "message", "text" => "here is the answer" }, posted_bodies.first)
      assert_equal "Bearer access-token", @http_requests.second["Authorization"]
    end

    should "post to the stored conversation id rather than to the thread key" do
      stub_http(token_response, http_response(200))
      thread_key = "#{PERSONAL_CONVERSATION_ID}#s=1700000000"
      event = stored_event(thread_key: thread_key, channel_id: PERSONAL_CONVERSATION_ID,
                           metadata: { service_url: SERVICE_URL,
                                       conversation_id: PERSONAL_CONVERSATION_ID })

      send_reply(event, "answer", thread_key: thread_key)

      assert_equal "#{SERVICE_URL}v3/conversations/#{PERSONAL_CONVERSATION_ID}/activities",
                   @http_uris.second.to_s
    end

    should "raise when the conversation being answered stored no reply metadata" do
      stub_http(token_response, http_response(200))
      event = stored_event(metadata: nil)

      assert_raises(TeamsAdapter::TeamsRequestError) { send_reply(event, "answer") }
      assert_empty @http_requests
    end

    should "split a long reply at a paragraph boundary" do
      stub_http(token_response, http_response(200))
      event = stored_event
      text = "#{"a" * 5000}\n\n#{"b" * 2000}"

      send_reply(event, text)

      assert_equal([ "a" * 5000, "b" * 2000 ], posted_bodies.map { |body| body["text"] })
    end

    should "split at a line boundary when there is no paragraph boundary" do
      stub_http(token_response, http_response(200))
      event = stored_event
      text = "#{"a" * 5000}\n#{"b" * 2000}"

      send_reply(event, text)

      assert_equal([ "a" * 5000, "b" * 2000 ], posted_bodies.map { |body| body["text"] })
    end

    should "cut hard when the text has no boundary at all" do
      stub_http(token_response, http_response(200))
      event = stored_event

      send_reply(event, "a" * 7000)

      assert_equal([ 6000, 1000 ], posted_bodies.map { |body| body["text"].length })
    end

    should "never cut inside an issue link" do
      stub_http(token_response, http_response(200))
      event = stored_event
      link = "[#1234](https://example.com/issues/1234)"
      text = ("a" * 5990) + link + ("b" * 100)

      send_reply(event, text)

      assert_equal "a" * 5990, posted_bodies.first["text"]
      assert_equal "#{link}#{"b" * 100}", posted_bodies.second["text"]
    end

    should "post the fragments in order through one conversation" do
      stub_http(token_response, http_response(200))
      event = stored_event
      text = "#{"a" * 5000}\n\n#{"b" * 5000}\n\n#{"c" * 5000}"

      send_reply(event, text)

      assert_equal([ "a" * 5000, "b" * 5000, "c" * 5000 ], posted_bodies.map { |body| body["text"] })
      assert_equal [ "#{SERVICE_URL}v3/conversations/#{CONVERSATION_ID}/activities" ] * 3,
                   @http_uris.drop(1).map(&:to_s)
    end
  end
end
