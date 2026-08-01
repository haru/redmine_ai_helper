# frozen_string_literal: true

# AiHelperMessage model for managing AI Helper messages
class AiHelperMessage < ApplicationRecord
  # Allowed values for the +role+ column. Messages with +role "context"+ are
  # imported from a chat channel and merged into a user message before LLM
  # handover (see AiHelperConversation#messages_for_openai).
  ROLES = [ "user", "assistant", "context" ].freeze

  # Role for messages imported from an external chat channel.
  CONTEXT_ROLE = "context"

  belongs_to :conversation, class_name: "AiHelperConversation", touch: true
  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
end
