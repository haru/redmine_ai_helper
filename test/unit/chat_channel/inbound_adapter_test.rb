# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

# Test-only reference inbound adapter (spec Assumptions): exercises the
# InboundAdapter contract without depending on any real chat service.
# Defined only in this test file so it never appears in the production
# settings screen or adapter registry outside of tests.
class ReferenceInboundAdapter < RedmineAiHelper::ChatChannel::InboundAdapter
  class << self
    def channel_type
      "reference_inbound"
    end

    def required_setting_fields
      [ :bot_token ]
    end

    # Class-level, not instance-level, because the webhook controller
    # instantiates its own throwaway adapter object per request: a test
    # configuring behavior before POSTing has no handle to that instance.
    attr_accessor :verify_result, :events_to_parse, :challenge_result

    def reset!
      self.verify_result = true
      self.events_to_parse = []
      self.challenge_result = nil
    end
  end

  attr_reader :sent_messages

  def initialize
    super
    @sent_messages = []
  end

  def verify_request(_request)
    self.class.verify_result
  end

  def parse_events(_request)
    self.class.events_to_parse || []
  end

  def challenge_response(_request)
    self.class.challenge_result
  end

  def send_message(channel_id:, thread_key:, text:)
    @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
  end
end

class ChatChannelInboundAdapterTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  setup { ReferenceInboundAdapter.reset! }

  def create_pending_event(overrides = {})
    AiHelperInboundEvent.create!(
      {
        channel_type: "reference_inbound", event_key: SecureRandom.hex(4), text: "hello",
        channel_id: "RC1", thread_key: "RC1:T1", received_at: Time.current
      }.merge(overrides)
    )
  end

  # Stubs the wait step so #start's loop runs exactly one poll cycle: the
  # stub's side effect calls #stop, which the loop observes on its next
  # condition check.
  def stub_dispatch_stop(adapter)
    ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)
  end

  context "capability declaration" do
    should "declare inbound? as true" do
      assert RedmineAiHelper::ChatChannel::InboundAdapter.inbound?
    end
  end

  context "abstract methods" do
    should "raise NotImplementedError from #verify_request when not overridden" do
      adapter = Class.new(RedmineAiHelper::ChatChannel::InboundAdapter) do
        class << self
          def channel_type
            "unimplemented_inbound"
          end
        end
      end.new

      error = assert_raises(NotImplementedError) { adapter.verify_request(nil) }
      assert_match(/verify_request/, error.message)
    end

    should "raise NotImplementedError from #parse_events when not overridden" do
      adapter = Class.new(RedmineAiHelper::ChatChannel::InboundAdapter) do
        class << self
          def channel_type
            "unimplemented_inbound2"
          end
        end
      end.new

      error = assert_raises(NotImplementedError) { adapter.parse_events(nil) }
      assert_match(/parse_events/, error.message)
    end

    should "default #challenge_response to nil" do
      adapter = Class.new(RedmineAiHelper::ChatChannel::InboundAdapter) do
        class << self
          def channel_type
            "unimplemented_inbound3"
          end
        end
      end.new

      assert_nil adapter.challenge_response(nil)
    end
  end

  context "#start" do
    should "claim and dispatch a pending event in one polling cycle, then stop" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      create(:ai_helper_chat_adapter_setting, channel_type: "reference_inbound", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "reference_inbound", channel_id: "RC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "reference answer")
      )
      event = create_pending_event
      adapter = ReferenceInboundAdapter.new
      ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)

      Timeout.timeout(5) { adapter.start }

      assert_equal "processed", event.reload.status
      assert_equal [ { channel_id: "RC1", thread_key: "RC1:T1", text: "reference answer" } ],
                   adapter.sent_messages
    end

    should "exit the loop once #stop has been called" do
      adapter = ReferenceInboundAdapter.new
      ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)

      assert_nothing_raised { Timeout.timeout(5) { adapter.start } }
      assert adapter.send(:stopped?)
    end

    should "keep polling and log the error instead of stopping when one event raises" do
      create_pending_event(event_key: "boom")
      adapter = ReferenceInboundAdapter.new
      adapter.stubs(:dispatch).raises(StandardError, "handler exploded")
      logger = mock("logger")
      logger.expects(:error).with(regexp_matches(/handler exploded/))
      adapter.stubs(:ai_helper_logger).returns(logger)
      ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)

      assert_nothing_raised { Timeout.timeout(5) { adapter.start } }
    end
  end

  context "#reply_metadata_for" do
    should "return the parsed reply_metadata of the most recently claimed event for the thread" do
      event = create_pending_event(reply_metadata: { reply_token: "abc" }.to_json)
      event.claim

      metadata = ReferenceInboundAdapter.new.reply_metadata_for(thread_key: "RC1:T1")

      assert_equal({ "reply_token" => "abc" }, metadata)
    end

    should "return nil when no claimed event exists for the thread" do
      metadata = ReferenceInboundAdapter.new.reply_metadata_for(thread_key: "RC1:none")

      assert_nil metadata
    end

    should "return nil when the claimed event has no reply_metadata" do
      event = create_pending_event
      event.claim

      metadata = ReferenceInboundAdapter.new.reply_metadata_for(thread_key: "RC1:T1")

      assert_nil metadata
    end
  end

  context "freshness limit (FR-008a)" do
    should "expire and discard an event received before the freshness limit, without dispatching it" do
      old_event = create_pending_event(
        event_key: "stale-1",
        received_at: (RedmineAiHelper::ChatChannel::InboundAdapter::FRESHNESS_LIMIT_SECONDS + 10).seconds.ago
      )
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal "expired", old_event.reload.status
      assert_empty adapter.sent_messages
    end

    should "log the discard of an expired event" do
      create_pending_event(
        event_key: "stale-2",
        received_at: (RedmineAiHelper::ChatChannel::InboundAdapter::FRESHNESS_LIMIT_SECONDS + 10).seconds.ago
      )
      adapter = ReferenceInboundAdapter.new
      logger = mock("logger")
      logger.expects(:info).with(regexp_matches(/stale-2/))
      adapter.stubs(:ai_helper_logger).returns(logger)
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }
    end

    should "process an event received within the freshness limit" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      create(:ai_helper_chat_adapter_setting, channel_type: "reference_inbound", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "reference_inbound", channel_id: "RC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "still fresh")
      )
      fresh_event = create_pending_event(
        event_key: "fresh-1",
        received_at: (RedmineAiHelper::ChatChannel::InboundAdapter::FRESHNESS_LIMIT_SECONDS - 10).seconds.ago
      )
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal "processed", fresh_event.reload.status
      assert_equal [ { channel_id: "RC1", thread_key: "RC1:T1", text: "still fresh" } ], adapter.sent_messages
    end
  end

  context "retention cleanup (FR-009)" do
    should "delete rows past the retention period on the first cycle and keep newer rows" do
      old_row = create_pending_event(
        event_key: "ret-old", status: "expired",
        received_at: (RedmineAiHelper::ChatChannel::InboundAdapter::RETENTION_DAYS.days + 1.day).ago
      )
      recent_row = create_pending_event(event_key: "ret-recent", status: "expired", received_at: 1.day.ago)
      adapter = ReferenceInboundAdapter.new
      ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)

      Timeout.timeout(5) { adapter.start }

      assert_not AiHelperInboundEvent.exists?(old_row.id)
      assert AiHelperInboundEvent.exists?(recent_row.id)
    end

    should "not purge again before CLEANUP_INTERVAL_SECONDS has elapsed since the last purge" do
      # Drives the private cleanup step directly, rather than through #start,
      # so the narrow Process.clock_gettime stub below does not also have to
      # account for every other call Rails makes to it during a full cycle.
      adapter = ReferenceInboundAdapter.new
      interval = RedmineAiHelper::ChatChannel::InboundAdapter::CLEANUP_INTERVAL_SECONDS
      AiHelperInboundEvent.expects(:purge_old).with("reference_inbound", anything).once

      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0)
      adapter.send(:purge_expired_rows_if_due)

      Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(1000.0 + interval - 1)
      adapter.send(:purge_expired_rows_if_due)
    end
  end

  context "gateway-stop recovery (FR-008)" do
    should "process an event that was saved while polling was stopped, once polling resumes within the freshness limit" do
      project = Project.find(1)
      project.enable_module!("ai_helper")
      user = User.find(2)
      create(:ai_helper_chat_adapter_setting, channel_type: "reference_inbound", redmine_user_id: user.id)
      create(:ai_helper_channel_binding, channel_type: "reference_inbound", channel_id: "RC1", project: project)
      RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
        AiHelperMessage.new(role: "assistant", content: "caught up after downtime")
      )
      # Simulates an event received while the gateway process was down: it
      # sat pending for a while, but is still inside the freshness window
      # once polling resumes.
      event = create_pending_event(event_key: "downtime-1", received_at: 90.seconds.ago)
      adapter = ReferenceInboundAdapter.new
      ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)

      Timeout.timeout(5) { adapter.start }

      assert_equal "processed", event.reload.status
      assert_equal [ { channel_id: "RC1", thread_key: "RC1:T1", text: "caught up after downtime" } ],
                   adapter.sent_messages
    end
  end
end

# FR-012 / SC-007: proves the inbound foundation works end to end - receive,
# persist, poll, dispatch, reply - through the reference adapter alone, with
# zero changes to Gateway, MessageHandler, IncomingMessage or an existing
# (Slack/Discord) adapter.
class ChatChannelInboundAdapterEndToEndTest < ActionController::TestCase
  include FactoryBot::Syntax::Methods
  tests AiHelperChatWebhookController

  def setup
    @controller = AiHelperChatWebhookController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create

    ReferenceInboundAdapter.reset!
    AiHelperInboundEvent.delete_all
    AiHelperChatAdapterSetting.delete_all
  end

  should "carry a webhook POST through storage, polling and dispatch to send_message" do
    project = Project.find(1)
    project.enable_module!("ai_helper")
    user = User.find(2)
    create(:ai_helper_chat_adapter_setting, channel_type: "reference_inbound", enabled: true,
                                             bot_token: "secret", redmine_user_id: user.id, default_project_id: project.id)
    create(:ai_helper_channel_binding, channel_type: "reference_inbound", channel_id: "E2E1", project: project)
    RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
      AiHelperMessage.new(role: "assistant", content: "end to end answer")
    )
    ReferenceInboundAdapter.events_to_parse = [
      { event_key: "e2e-1", text: "hello from e2e", channel_id: "E2E1", thread_key: "E2E1:T1" }
    ]

    post :receive, params: { channel_type: "reference_inbound" }, body: "{}"

    assert_response :success
    event = AiHelperInboundEvent.find_by(channel_type: "reference_inbound", event_key: "e2e-1")
    assert_not_nil event
    assert_equal "pending", event.status

    adapter = ReferenceInboundAdapter.new
    ReferenceInboundAdapter.stubs(:timed_queue_pop).with { |_queue, _timeout| adapter.stop; true }.returns(nil)
    Timeout.timeout(5) { adapter.start }

    assert_equal "processed", event.reload.status
    assert_equal [ { channel_id: "E2E1", thread_key: "E2E1:T1", text: "end to end answer" } ], adapter.sent_messages
  end
end
