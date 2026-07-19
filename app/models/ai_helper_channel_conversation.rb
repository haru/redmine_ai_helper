# frozen_string_literal: true

# Mapping between an external chat tool thread and an AI helper conversation.
# One thread (channel_type + thread_key) maps to exactly one conversation.
class AiHelperChannelConversation < ApplicationRecord
  belongs_to :conversation, class_name: "AiHelperConversation"

  validates :channel_type, presence: true
  validates :thread_key, presence: true, uniqueness: { scope: :channel_type }
  validates :conversation, presence: true

  # Returns the conversation bound to the given thread, creating both the
  # conversation and the binding when the thread is seen for the first time.
  # The conversation owner stays the thread starter; later speakers are
  # represented by User.current at message processing time.
  # @param channel_type [String] Tool type (e.g. "slack")
  # @param thread_key [String] Tool-specific thread identifier
  # @param user [User] The user who starts the conversation
  # @return [AiHelperConversation] The bound conversation
  def self.find_or_create_conversation(channel_type:, thread_key:, user:)
    channel_conversation = find_by(channel_type: channel_type, thread_key: thread_key)
    return channel_conversation.conversation if channel_conversation

    conversation = AiHelperConversation.new(user: user, title: "-")
    transaction do
      conversation.save!
      create!(channel_type: channel_type, thread_key: thread_key, conversation: conversation)
    end
    conversation
  end
end
