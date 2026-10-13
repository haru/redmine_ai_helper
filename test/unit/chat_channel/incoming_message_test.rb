# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelIncomingMessageTest < ActiveSupport::TestCase
  IncomingMessage = RedmineAiHelper::ChatChannel::IncomingMessage

  def build(**overrides)
    IncomingMessage.new(
      **{ channel_type: "slack", channel_id: "C1", thread_key: "C1:1.0", text: "hi", message_ts: "1.0" }.merge(overrides)
    )
  end

  context "origin_channel_id" do
    should "default to channel_id when omitted" do
      assert_equal "C1", build.origin_channel_id
    end

    should "default to channel_id when nil" do
      assert_equal "C1", build(origin_channel_id: nil).origin_channel_id
    end

    should "return the explicit value" do
      assert_equal "T9", build(origin_channel_id: "T9").origin_channel_id
    end

    should "raise ArgumentError for an empty string" do
      assert_raises(ArgumentError) { build(origin_channel_id: "") }
    end

    should "raise ArgumentError for a non-String value" do
      [ 123, :sym ].each do |value|
        assert_raises(ArgumentError) { build(origin_channel_id: value) }
      end
    end

    should "keep the instance frozen" do
      assert_predicate build(origin_channel_id: "T9"), :frozen?
    end
  end
end
