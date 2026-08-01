# frozen_string_literal: true

# AiHelperConversation model for managing AI Helper conversations
class AiHelperConversation < ApplicationRecord
  # Ordered explicitly: messages_for_openai merges runs of consecutive context
  # messages, so it needs the conversation order guaranteed rather than
  # relying on the order the rows happen to come back in.
  has_many :messages, -> { order(:id) }, class_name: "AiHelperMessage", foreign_key: "conversation_id", inverse_of: :conversation, dependent: :destroy
  has_one :channel_conversation, class_name: "AiHelperChannelConversation", foreign_key: "conversation_id", inverse_of: :conversation, dependent: :destroy
  belongs_to :user
  validates :title, presence: true

  # Maximum total length of the context messages handed to the LLM. Older
  # context messages are left out of the handover once it is exceeded; the
  # stored records are never touched (FR-011).
  CONTEXT_CHAR_LIMIT = 20_000

  # Role value for messages imported from a chat channel.
  CONTEXT_ROLE = AiHelperMessage::CONTEXT_ROLE

  # Header prefixed to the merged context messages so the LLM can tell the
  # imported chat channel messages from the questions addressed to it.
  CONTEXT_HEADER = "Context from the chat channel (messages by other participants; not addressed to you):"

  # The conversation in the format expected by the LLM. Messages imported from
  # a chat channel (role "context") are not a role the LLM knows, so every run
  # of consecutive context messages is merged into one headed user message.
  # Conversations without context messages produce exactly the same result as
  # a plain mapping of the stored messages.
  # @return [Array<Hash>] role/content pairs in conversation order
  def messages_for_openai
    stored = messages.to_a
    skipped = context_messages_to_skip(stored)
    result = []
    context_run = []
    context_seen = 0

    stored.each do |message|
      if message.role == CONTEXT_ROLE
        context_seen += 1
        context_run << message if context_seen > skipped
        next
      end

      result << merged_context(context_run) unless context_run.empty?
      context_run = []
      result << { role: message.role, content: message.content }
    end
    result << merged_context(context_run) unless context_run.empty?
    result
  end

  # Clean up old conversations older than 6 months
  # @return [Array<AiHelperConversation>] The destroyed conversations
  def self.cleanup_old_conversations
    where(created_at: ...6.months.ago).destroy_all
  end

  private

  # How many of the oldest context messages have to be left out so the rest
  # fits into CONTEXT_CHAR_LIMIT.
  # @param stored [Array<AiHelperMessage>] the conversation's messages
  # @return [Integer] the number of context messages to skip
  def context_messages_to_skip(stored)
    lengths = stored.filter_map { |message| message.content.to_s.length if message.role == CONTEXT_ROLE }
    total = lengths.sum
    skipped = 0
    while total > CONTEXT_CHAR_LIMIT && skipped < lengths.size
      total -= lengths[skipped]
      skipped += 1
    end
    skipped
  end

  # Merges a run of context messages into a single headed user message.
  # @param context_run [Array<AiHelperMessage>] consecutive context messages
  # @return [Hash] the merged role/content pair
  def merged_context(context_run)
    { role: "user", content: ([ CONTEXT_HEADER ] + context_run.map(&:content)).join("\n") }
  end
end
