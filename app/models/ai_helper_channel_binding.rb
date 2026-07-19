# frozen_string_literal: true

# Binding between an external chat tool channel and a Redmine project.
# One channel (channel_type + channel_id) maps to exactly one project.
class AiHelperChannelBinding < ApplicationRecord
  belongs_to :project

  validates :channel_type, presence: true
  validates :channel_id, presence: true, uniqueness: { scope: :channel_type }

  scope :for_channel, ->(channel_type, channel_id) {
          where(channel_type: channel_type, channel_id: channel_id)
        }
end
