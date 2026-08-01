# frozen_string_literal: true

# Mapping between an external chat tool thread and an AI helper conversation.
# One thread (channel_type + thread_key) maps to exactly one conversation.
#
# @!attribute [rw] last_imported_message_key
#   The external message id (IncomingMessage#message_ts) of the most recent
#   mention whose surrounding messages were imported into the conversation.
#   Everything up to that message is already stored, so the next import only
#   asks for messages after it, which rules out duplicates within a
#   conversation and survives a gateway restart. The value is an opaque,
#   adapter-specific string (Slack ts, Discord snowflake) that is only ever
#   passed back to the adapter. nil means nothing has been imported yet, which
#   is a normal state and therefore not validated.
#   @return [String, nil]
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
