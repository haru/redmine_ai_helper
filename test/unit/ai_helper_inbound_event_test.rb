# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperInboundEventTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  def build_event(overrides = {})
    AiHelperInboundEvent.new(
      {
        channel_type: "webhook_test",
        event_key: "evt-1",
        text: "hello",
        channel_id: "C1",
        thread_key: "C1:T1",
        received_at: Time.current
      }.merge(overrides)
    )
  end

  context "validations" do
    should "require channel_type, event_key, text, channel_id, thread_key and received_at" do
      event = AiHelperInboundEvent.new

      assert_not event.valid?
      %i[channel_type event_key text channel_id thread_key received_at].each do |attr|
        assert_includes event.errors.attribute_names, attr, "expected #{attr} to be required"
      end
    end

    should "only accept pending, processed or expired as status" do
      event = build_event(status: "bogus")

      assert_not event.valid?
      assert_includes event.errors.attribute_names, :status
    end

    should "default status to pending" do
      event = build_event
      event.save!

      assert_equal "pending", event.status
    end

    should "reject a duplicate event_key within the same channel_type" do
      build_event.save!
      duplicate = build_event

      assert_not duplicate.valid?
      assert_includes duplicate.errors.attribute_names, :event_key
    end

    should "allow the same event_key across different channel_types" do
      build_event.save!
      other_channel = build_event(channel_type: "other_webhook_test")

      assert other_channel.valid?
    end
  end

  context ".record_event" do
    should "persist a pending event" do
      event = AiHelperInboundEvent.record_event(
        channel_type: "webhook_test", event_key: "evt-2", text: "hi",
        channel_id: "C1", thread_key: "C1:T1", received_at: Time.current
      )

      assert event.persisted?
      assert_equal "pending", event.status
    end

    should "return nil when the same channel_type/event_key is inserted concurrently (RecordNotUnique)" do
      build_event(event_key: "evt-3").save!

      result = AiHelperInboundEvent.record_event(
        channel_type: "webhook_test", event_key: "evt-3", text: "hi",
        channel_id: "C1", thread_key: "C1:T1", received_at: Time.current
      )

      assert_nil result
      assert_equal 1, AiHelperInboundEvent.where(channel_type: "webhook_test", event_key: "evt-3").count
    end

    should "raise when the event is invalid for a reason other than duplication" do
      assert_raises(ActiveRecord::RecordInvalid) do
        AiHelperInboundEvent.record_event(
          channel_type: "webhook_test", event_key: "evt-invalid", text: "",
          channel_id: "C1", thread_key: "C1:T1", received_at: Time.current
        )
      end

      assert_equal 0, AiHelperInboundEvent.where(event_key: "evt-invalid").count
    end

    should "store a Hash reply_metadata as JSON" do
      event = AiHelperInboundEvent.record_event(
        channel_type: "webhook_test", event_key: "evt-meta", text: "hi",
        channel_id: "C1", thread_key: "C1:T1", received_at: Time.current,
        reply_metadata: { "reply_token" => "tok" }
      )

      assert_equal({ "reply_token" => "tok" }, JSON.parse(event.reload.reply_metadata))
    end
  end

  context "#reply_metadata=" do
    should "serialize a Hash to JSON, as the adapter contract promises" do
      event = build_event(event_key: "evt-hash-meta", reply_metadata: { "reply_token" => "abc" })
      event.save!

      assert_equal({ "reply_token" => "abc" }, JSON.parse(event.reload.reply_metadata))
    end

    should "keep a String that is already JSON as given" do
      event = build_event(event_key: "evt-string-meta", reply_metadata: '{"reply_token":"abc"}')
      event.save!

      assert_equal '{"reply_token":"abc"}', event.reload.reply_metadata
    end

    should "keep nil as nil" do
      event = build_event(event_key: "evt-nil-meta", reply_metadata: nil)
      event.save!

      assert_nil event.reload.reply_metadata
    end
  end

  context ".pending_for" do
    should "return only pending rows for the given channel_type, oldest received_at first" do
      newer = build_event(event_key: "evt-newer", received_at: 1.minute.ago)
      newer.save!
      older = build_event(event_key: "evt-older", received_at: 2.minutes.ago)
      older.save!
      build_event(event_key: "evt-other-channel", channel_type: "other_webhook_test").save!
      processed = build_event(event_key: "evt-processed", status: "processed")
      processed.save!

      result = AiHelperInboundEvent.pending_for("webhook_test", limit: 20)

      assert_equal [ older.id, newer.id ], result.map(&:id)
    end

    should "cap the result at the given limit" do
      3.times { |i| build_event(event_key: "evt-limit-#{i}").save! }

      result = AiHelperInboundEvent.pending_for("webhook_test", limit: 2)

      assert_equal 2, result.size
    end
  end

  context ".purge_old" do
    should "delete rows received before the given time and keep newer rows" do
      old = build_event(event_key: "evt-old", received_at: 10.days.ago)
      old.save!
      recent = build_event(event_key: "evt-recent", received_at: 1.day.ago)
      recent.save!

      AiHelperInboundEvent.purge_old("webhook_test", before: 7.days.ago)

      assert_not AiHelperInboundEvent.exists?(old.id)
      assert AiHelperInboundEvent.exists?(recent.id)
    end

    should "not delete rows of a different channel_type" do
      other = build_event(event_key: "evt-other", channel_type: "other_webhook_test", received_at: 10.days.ago)
      other.save!

      AiHelperInboundEvent.purge_old("webhook_test", before: 7.days.ago)

      assert AiHelperInboundEvent.exists?(other.id)
    end
  end

  context "#claim" do
    should "atomically move a pending row to processed and return true" do
      event = build_event
      event.save!

      assert event.claim
      assert_equal "processed", event.reload.status
    end

    should "return false and leave the row untouched when it is not pending (double claim protection, INV-I3)" do
      event = build_event
      event.save!
      assert event.claim

      second_attempt = AiHelperInboundEvent.find(event.id)

      assert_not second_attempt.claim
      assert_equal "processed", event.reload.status
    end
  end

  context "#expire!" do
    should "set status to expired" do
      event = build_event
      event.save!

      event.expire!

      assert_equal "expired", event.reload.status
    end
  end

  context "#expired_by?" do
    should "be true when received_at is older than the given number of seconds" do
      event = build_event(received_at: 130.seconds.ago)

      assert event.expired_by?(120)
    end

    should "be false when received_at is within the given number of seconds" do
      event = build_event(received_at: 10.seconds.ago)

      assert_not event.expired_by?(120)
    end
  end

  context "#to_incoming_message" do
    should "build an IncomingMessage carrying the normalized fields" do
      event = build_event(
        channel_type: "webhook_test", channel_id: "C1", thread_key: "C1:T1",
        message_ts: "T1-1", text: "hello there", dm: true, in_thread: true
      )

      message = event.to_incoming_message

      assert_kind_of RedmineAiHelper::ChatChannel::IncomingMessage, message
      assert_equal "webhook_test", message.channel_type
      assert_equal "C1", message.channel_id
      assert_equal "C1:T1", message.thread_key
      assert_equal "T1-1", message.message_ts
      assert_equal "hello there", message.text
      assert message.dm?
      assert message.in_thread?
    end

    # The id is what lets InboundAdapter#reply_metadata_for resolve the exact
    # event a reply is answering, so it has to survive the trip through the
    # gateway queue with the message.
    should "carry the row id so the reply can be tied back to this event" do
      event = build_event
      event.save!

      message = event.to_incoming_message

      assert_kind_of RedmineAiHelper::ChatChannel::InboundEventMessage, message
      assert_equal event.id, message.event_id
      # IncomingMessage freezes itself, so event_id must be assigned before
      # the superclass initializer runs.
      assert message.frozen?
    end
  end
end
