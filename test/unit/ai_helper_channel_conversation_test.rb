# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperChannelConversationTest < ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods

  fixtures :users

  context "validations" do
    should "require channel_type, thread_key and conversation" do
      channel_conversation = AiHelperChannelConversation.new

      assert_not channel_conversation.valid?
      assert_predicate channel_conversation.errors[:channel_type], :present?
      assert_predicate channel_conversation.errors[:thread_key], :present?
      assert_predicate channel_conversation.errors[:conversation], :present?
    end

    should "reject a duplicate thread_key for the same channel_type" do
      create(:ai_helper_channel_conversation, thread_key: "C1:100.000001")
      duplicate = build(:ai_helper_channel_conversation, thread_key: "C1:100.000001")

      assert_not duplicate.valid?
      assert_predicate duplicate.errors[:thread_key], :present?
    end

    should "allow the same thread_key for a different channel_type" do
      create(:ai_helper_channel_conversation, thread_key: "C1:100.000001")
      other = build(:ai_helper_channel_conversation, channel_type: "discord", thread_key: "C1:100.000001")

      assert_predicate other, :valid?
    end
  end

  context "find_or_create_conversation" do
    should "create a new conversation owned by the given user" do
      user = User.find(2)
      conversation = AiHelperChannelConversation.find_or_create_conversation(
        channel_type: "slack", thread_key: "C9:200.000001", user: user
      )

      assert_predicate conversation, :persisted?
      assert_equal user, conversation.user
      channel_conversation = AiHelperChannelConversation.find_by(channel_type: "slack", thread_key: "C9:200.000001")
      assert_equal conversation, channel_conversation.conversation
    end

    should "return the existing conversation for a known thread" do
      user = User.find(2)
      first = AiHelperChannelConversation.find_or_create_conversation(
        channel_type: "slack", thread_key: "C9:200.000002", user: user
      )
      second = AiHelperChannelConversation.find_or_create_conversation(
        channel_type: "slack", thread_key: "C9:200.000002", user: User.find(3)
      )

      assert_equal first.id, second.id
      assert_equal 1, AiHelperChannelConversation.where(thread_key: "C9:200.000002").count
    end

    should "keep the original owner when another user continues the thread" do
      starter = User.find(2)
      AiHelperChannelConversation.find_or_create_conversation(
        channel_type: "slack", thread_key: "C9:200.000003", user: starter
      )
      conversation = AiHelperChannelConversation.find_or_create_conversation(
        channel_type: "slack", thread_key: "C9:200.000003", user: User.find(3)
      )

      assert_equal starter, conversation.user
    end
  end

  context "last_imported_message_key" do
    should "default to nil for a newly created channel conversation" do
      channel_conversation = create(:ai_helper_channel_conversation)

      assert_nil channel_conversation.last_imported_message_key
    end

    should "persist the import cursor" do
      channel_conversation = create(:ai_helper_channel_conversation)

      channel_conversation.update!(last_imported_message_key: "1700000000.000500")

      assert_equal "1700000000.000500", channel_conversation.reload.last_imported_message_key
    end
  end

  context "conversation deletion" do
    should "delete the channel conversation when the conversation is destroyed" do
      channel_conversation = create(:ai_helper_channel_conversation)

      channel_conversation.conversation.destroy

      assert_nil AiHelperChannelConversation.find_by(id: channel_conversation.id)
    end
  end
end
