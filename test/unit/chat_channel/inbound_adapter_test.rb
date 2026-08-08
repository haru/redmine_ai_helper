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

    # Error #send_message raises on its first call, to exercise the failure
    # notice MessageHandler posts through a second #send_message.
    attr_accessor :send_failure

    # When set, #send_message asks for reply metadata with this thread key
    # instead of the one it was called with, to exercise the mismatch guard.
    attr_accessor :probe_thread_key

    def reset!
      self.verify_result = true
      self.events_to_parse = []
      self.challenge_result = nil
      self.send_failure = nil
      self.probe_thread_key = nil
    end
  end

  attr_reader :sent_messages, :sent_metadata

  def initialize
    super
    @sent_messages = []
    @sent_metadata = []
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

  # Reads the reply metadata the way a real adapter does: from inside
  # #send_message, which is the only point at which a platform needing a
  # reply token has to know it.
  def send_message(channel_id:, thread_key:, text:)
    @sent_messages << { channel_id: channel_id, thread_key: thread_key, text: text }
    @sent_metadata << reply_metadata_for(thread_key: self.class.probe_thread_key || thread_key)
    raise self.class.send_failure if self.class.send_failure && @sent_messages.one?
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

  # Configures everything MessageHandler needs for a dispatched event to
  # reach #send_message, which is where reply metadata is read.
  def setup_reply_path(answer: "reference answer")
    project = Project.find(1)
    project.enable_module!("ai_helper")
    user = User.find(2)
    create(:ai_helper_chat_adapter_setting, channel_type: "reference_inbound", redmine_user_id: user.id)
    create(:ai_helper_channel_binding, channel_type: "reference_inbound", channel_id: "RC1", project: project)
    RedmineAiHelper::Llm.any_instance.stubs(:chat).returns(
      AiHelperMessage.new(role: "assistant", content: answer)
    )
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
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal "processed", event.reload.status
      assert_equal [ { channel_id: "RC1", thread_key: "RC1:T1", text: "reference answer" } ],
                   adapter.sent_messages
    end

    should "exit the loop once #stop has been called" do
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

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
      stub_dispatch_stop(adapter)

      assert_nothing_raised { Timeout.timeout(5) { adapter.start } }
    end
  end

  context "#reply_metadata_for" do
    should "return the parsed reply_metadata of the event being answered" do
      setup_reply_path
      create_pending_event(reply_metadata: { reply_token: "abc" }.to_json)
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ { "reply_token" => "abc" } ], adapter.sent_metadata
    end

    # The contract lets an adapter return :reply_metadata as a Hash; only the
    # column holds JSON. Passing a pre-encoded String (as the test above does)
    # would not exercise that conversion.
    should "return the metadata an adapter supplied as a Hash at parse time" do
      setup_reply_path
      create_pending_event(reply_metadata: { "reply_token" => "hash-token" })
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ { "reply_token" => "hash-token" } ], adapter.sent_metadata
    end

    # One poll cycle claims a whole batch before any of it is answered, so
    # several events of one thread are "processed" at the same time. Each
    # reply must still see the metadata of the event it is answering.
    should "give each event of a thread the metadata of that event" do
      setup_reply_path
      create_pending_event(event_key: "fifo-1", received_at: 20.seconds.ago,
                           reply_metadata: { "reply_token" => "first" })
      create_pending_event(event_key: "fifo-2", received_at: 10.seconds.ago,
                           reply_metadata: { "reply_token" => "second" })
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ { "reply_token" => "first" }, { "reply_token" => "second" } ], adapter.sent_metadata
    end

    # Regression: the reply position used to be a per-thread cursor held only
    # in the gateway process's memory. A restart reset it, so the first reply
    # in a thread picked up the oldest row still retained for deduplication -
    # an event answered up to RETENTION_DAYS ago - instead of the event being
    # answered now.
    should "not pick up an already answered event of the same thread after a gateway restart" do
      setup_reply_path
      answered_before_restart = create_pending_event(
        event_key: "answered-two-days-ago", status: "processed", received_at: 2.days.ago,
        reply_metadata: { "reply_token" => "long-since-expired" }
      )
      create_pending_event(event_key: "asked-now", reply_metadata: { "reply_token" => "current" })
      # A newly started gateway process knows nothing about the older event.
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ { "reply_token" => "current" } ], adapter.sent_metadata
      assert_equal "processed", answered_before_restart.reload.status
    end

    # Regression: MessageHandler posts a failure notice through a second
    # #send_message when the first one raises. That used to consume a second
    # event's metadata for a single event's reply.
    should "return the same metadata for every reply to one event" do
      setup_reply_path
      ReferenceInboundAdapter.send_failure = RuntimeError.new("the chat service is down")
      create_pending_event(reply_metadata: { "reply_token" => "only-token" })
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal 2, adapter.sent_messages.size, "the failure notice is a second send"
      assert_equal [ { "reply_token" => "only-token" }, { "reply_token" => "only-token" } ],
                   adapter.sent_metadata
    end

    should "return nil when the event being answered carries no reply_metadata" do
      setup_reply_path
      create_pending_event
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ nil ], adapter.sent_metadata
    end

    should "return nil for a thread other than the one being answered" do
      setup_reply_path
      ReferenceInboundAdapter.probe_thread_key = "RC1:SOME_OTHER_THREAD"
      create_pending_event(reply_metadata: { "reply_token" => "abc" })
      adapter = ReferenceInboundAdapter.new
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal [ nil ], adapter.sent_metadata
    end

    should "return nil when no reply is in progress" do
      create_pending_event(reply_metadata: { "reply_token" => "abc" }).claim

      assert_nil ReferenceInboundAdapter.new.reply_metadata_for(thread_key: "RC1:T1")
    end
  end

  context "poll batch size" do
    should "claim at most POLL_BATCH_SIZE events per cycle" do
      batch_size = RedmineAiHelper::ChatChannel::InboundAdapter::POLL_BATCH_SIZE
      (batch_size + 1).times { |i| create_pending_event(event_key: "batch-#{i}") }
      adapter = ReferenceInboundAdapter.new
      dispatched = 0
      adapter.stubs(:dispatch).with { |_message| dispatched += 1; true }
      stub_dispatch_stop(adapter)

      Timeout.timeout(5) { adapter.start }

      assert_equal batch_size, dispatched
      assert_equal 1, AiHelperInboundEvent.where(channel_type: "reference_inbound", status: "pending").count
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
      stub_dispatch_stop(adapter)

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
      stub_dispatch_stop(adapter)

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
    # reply_metadata is supplied as the Hash the adapter contract defines, so
    # this covers the Hash -> JSON column -> parsed Hash round trip an adapter
    # that needs a reply token actually depends on.
    ReferenceInboundAdapter.events_to_parse = [
      { event_key: "e2e-1", text: "hello from e2e", channel_id: "E2E1", thread_key: "E2E1:T1",
        reply_metadata: { "reply_token" => "e2e-token" } }
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
    assert_equal [ { "reply_token" => "e2e-token" } ], adapter.sent_metadata
  end
end
