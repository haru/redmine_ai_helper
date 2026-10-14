# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)

class ChatChannelIncomingMessageTest < ActiveSupport::TestCase
  IncomingMessage = RedmineAiHelper::ChatChannel::IncomingMessage

  def build(**overrides)
    IncomingMessage.new(
      **{ channel_type: "slack", channel_id: "C1", thread_key: "C1:1.0", text: "hi", message_ts: "1.0" }.merge(overrides)
    )
  end

  should "be frozen" do
    assert_predicate build, :frozen?
  end
end
