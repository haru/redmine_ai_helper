# frozen_string_literal: true

# AiHelperMessage model for managing AI Helper messages
class AiHelperMessage < ApplicationRecord
  belongs_to :conversation, class_name: "AiHelperConversation", touch: true
  validates :content, presence: true
  validates :role, presence: true
end
