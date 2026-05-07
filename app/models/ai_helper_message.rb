# frozen_string_literal: true

# AiHelperMessage model for managing AI Helper messages
class AiHelperMessage < ApplicationRecord
  belongs_to :conversation, class_name: "AiHelperConversation", foreign_key: "conversation_id", touch: true
  validates :content, presence: true
  validates :role, presence: true
  validates :conversation_id, presence: true
end
