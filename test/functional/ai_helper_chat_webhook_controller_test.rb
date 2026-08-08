# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

# Test-only reference inbound adapter with class-level toggles: the
# controller instantiates a fresh adapter object per request, so the fakes
# it needs to configure (verification result, parsed events, challenge
# response) live on the class rather than an instance the test never gets a
# handle to. Defined only in this test file (spec Assumptions).
class WebhookReferenceAdapter < RedmineAiHelper::ChatChannel::InboundAdapter
  class << self
    def channel_type
      "webhook_reference"
    end

    def required_setting_fields
      [ :bot_token ]
    end

    attr_accessor :verify_result, :events_to_parse, :challenge_result, :parse_error

    def reset!
      self.verify_result = true
      self.events_to_parse = []
      self.challenge_result = nil
      self.parse_error = nil
    end
  end

  def verify_request(_request)
    self.class.verify_result
  end

  def parse_events(_request)
    raise self.class.parse_error if self.class.parse_error

    self.class.events_to_parse
  end

  def challenge_response(_request)
    self.class.challenge_result
  end

  def send_message(channel_id:, thread_key:, text:); end
end

class AiHelperChatWebhookControllerTest < ActionController::TestCase
  fixtures :projects, :users

  def setup
    @controller = AiHelperChatWebhookController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create

    WebhookReferenceAdapter.reset!
    AiHelperInboundEvent.delete_all
    AiHelperChatAdapterSetting.delete_all
    AiHelperChatAdapterSetting.create!(
      channel_type: "webhook_reference", enabled: true, bot_token: "secret-token",
      redmine_user_id: 2, dm_default_project_id: 1
    )
  end

  def valid_event(overrides = {})
    { event_key: "evt-1", text: "hello", channel_id: "C1", thread_key: "C1:T1" }.merge(overrides)
  end

  context "unknown channel_type" do
    should "return 404 and save nothing" do
      post :receive, params: { channel_type: "does_not_exist" }, body: "{}"

      assert_response :not_found
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "non-inbound adapter" do
    should "return 404 for a registered adapter that does not declare inbound?" do
      post :receive, params: { channel_type: "slack" }, body: "{}"

      assert_response :not_found
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "disabled adapter" do
    should "return 404 when the inbound adapter is not enabled (US2-2)" do
      AiHelperChatAdapterSetting.for_channel("webhook_reference").update_column(:enabled, false)
      WebhookReferenceAdapter.events_to_parse = [ valid_event ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :not_found
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "verification" do
    should "return 401 and save nothing when verify_request fails (FR-002)" do
      WebhookReferenceAdapter.verify_result = false
      WebhookReferenceAdapter.events_to_parse = [ valid_event ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :unauthorized
      assert_equal 0, AiHelperInboundEvent.count
    end

    should "not answer the connectivity handshake when verification fails (order of steps 4 and 5)" do
      WebhookReferenceAdapter.verify_result = false
      WebhookReferenceAdapter.challenge_result = { status: 200, content_type: "text/plain", body: "challenge-echo" }

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :unauthorized
      assert_not_equal "challenge-echo", @response.body
    end
  end

  context "challenge response (FR-013)" do
    should "return the adapter-specified response and save nothing" do
      WebhookReferenceAdapter.challenge_result = { status: 200, content_type: "text/plain", body: "challenge-echo" }

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal "challenge-echo", @response.body
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "normal event delivery" do
    should "return 200 and persist a pending row for a valid request" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event ]

      post :receive, params: { channel_type: "webhook_reference" }, body: '{"event":"payload"}'

      assert_response :success
      assert_equal 1, AiHelperInboundEvent.count
      event = AiHelperInboundEvent.last
      assert_equal "webhook_reference", event.channel_type
      assert_equal "pending", event.status
      assert_equal "hello", event.text
    end

    should "save one row per event when a single request carries multiple events (Q3)" do
      WebhookReferenceAdapter.events_to_parse = [
        valid_event(event_key: "evt-a"), valid_event(event_key: "evt-b")
      ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 2, AiHelperInboundEvent.count
    end

    should "return 200 and save nothing when the request carries zero events" do
      WebhookReferenceAdapter.events_to_parse = []

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "duplicate events (FR-006)" do
    should "return 200 on a resend of the same event_key without adding a row" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-dup") ]
      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"
      assert_equal 1, AiHelperInboundEvent.count

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 1, AiHelperInboundEvent.count
    end

    should "save only the new events when a request mixes an existing and a new event_key" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-existing") ]
      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      WebhookReferenceAdapter.events_to_parse = [
        valid_event(event_key: "evt-existing"), valid_event(event_key: "evt-fresh")
      ]
      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 2, AiHelperInboundEvent.count
    end
  end

  context "unparseable payload" do
    should "return 200 and save nothing when parse_events raises (prevents a resend loop)" do
      WebhookReferenceAdapter.parse_error = StandardError.new("garbled payload")

      post :receive, params: { channel_type: "webhook_reference" }, body: "not json"

      assert_response :success
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "unstorable event" do
    should "log an error and still return 200 when an event fails validation" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(text: "") ]
      RedmineAiHelper::CustomLogger.instance.expects(:error).with(regexp_matches(/failed to store event/))

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 0, AiHelperInboundEvent.count
    end

    should "store the remaining events when one carries a key outside the event contract" do
      WebhookReferenceAdapter.events_to_parse = [
        valid_event(event_key: "evt-bad", user_id: "U1"), valid_event(event_key: "evt-good")
      ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal [ "evt-good" ], AiHelperInboundEvent.pluck(:event_key)
    end

    should "reject an event that carries received_at so the adapter cannot move the freshness clock" do
      WebhookReferenceAdapter.events_to_parse = [
        valid_event(event_key: "evt-backdated", received_at: 3.days.ago), valid_event(event_key: "evt-good")
      ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal [ "evt-good" ], AiHelperInboundEvent.pluck(:event_key)
    end

    should "reject an event that carries status so the adapter cannot skip the queue" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-preprocessed", status: "processed") ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 0, AiHelperInboundEvent.count
    end

    should "reject an event that carries channel_type so the adapter cannot write outside its own channel" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-other", channel_type: "slack") ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 0, AiHelperInboundEvent.count
    end
  end

  context "received_at" do
    should "be stamped by the receiving side at receive time" do
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-stamped") ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_in_delta Time.current, AiHelperInboundEvent.last.received_at, 5.seconds
    end
  end

  context "reply metadata" do
    should "store a Hash returned by parse_events as JSON (adapter contract)" do
      WebhookReferenceAdapter.events_to_parse = [
        valid_event(event_key: "evt-meta", reply_metadata: { "reply_token" => "tok-1" })
      ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal({ "reply_token" => "tok-1" }, JSON.parse(AiHelperInboundEvent.last.reply_metadata))
    end
  end

  context "login_required" do
    should "receive the event even when Setting.login_required is on (Issue #304)" do
      Setting.login_required = "1"
      WebhookReferenceAdapter.events_to_parse = [ valid_event(event_key: "evt-login") ]

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert_response :success
      assert_equal 1, AiHelperInboundEvent.count
    ensure
      Setting.login_required = "0"
    end
  end

  context "logging (FR-007)" do
    should "log a warning for an unknown channel_type without leaking secrets" do
      RedmineAiHelper::CustomLogger.instance.expects(:warn).with(regexp_matches(/does_not_exist/))

      post :receive, params: { channel_type: "does_not_exist" }, body: "{}"
    end

    should "log a warning for a disabled adapter" do
      AiHelperChatAdapterSetting.for_channel("webhook_reference").update_column(:enabled, false)
      RedmineAiHelper::CustomLogger.instance.expects(:warn).with(regexp_matches(/webhook_reference/))

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"
    end

    should "log a warning for a failed verification without the token or signature" do
      WebhookReferenceAdapter.verify_result = false
      logged = []
      RedmineAiHelper::CustomLogger.instance.stubs(:warn).with { |message| logged << message; true }

      post :receive, params: { channel_type: "webhook_reference" }, body: "{}"

      assert(logged.any? { |m| m.include?("webhook_reference") })
      assert(logged.none? { |m| m.include?("secret-token") })
    end
  end
end
