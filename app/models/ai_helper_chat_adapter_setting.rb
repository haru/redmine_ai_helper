# frozen_string_literal: true

# Per-adapter settings for external chat tool integrations. One row per
# adapter (channel_type, e.g. "slack"). Follows the same pattern as
# AiHelperModelProfile: typed columns shared by all adapters, with per-adapter
# required fields declared by the adapter class itself.
class AiHelperChatAdapterSetting < ApplicationRecord
  include Redmine::SafeAttributes

  belongs_to :dm_default_project, class_name: "Project", optional: true

  validates :channel_type, presence: true, uniqueness: true
  validate :required_fields_present_when_enabled

  safe_attributes "enabled", "app_token", "bot_token", "dm_default_project_id"

  class << self
    # Returns the setting row for the given adapter, or a new unsaved record
    # when the adapter has no settings yet.
    # @param channel_type [String] Adapter identifier (e.g. "slack")
    # @return [AiHelperChatAdapterSetting]
    def for_channel(channel_type)
      find_by(channel_type: channel_type) || new(channel_type: channel_type)
    end

    # Returns whether the integration for the given adapter is enabled.
    # @param channel_type [String] Adapter identifier (e.g. "slack")
    # @return [Boolean]
    def enabled?(channel_type)
      for_channel(channel_type).enabled
    end
  end

  # Masked app token for display (all but the first four characters hidden).
  # @return [String, nil]
  def masked_app_token
    mask_token(app_token)
  end

  # Masked bot token for display (all but the first four characters hidden).
  # @return [String, nil]
  def masked_bot_token
    mask_token(bot_token)
  end

  private

  # Fields declared as required by the adapter registered for this
  # channel_type. Empty when no adapter is registered.
  def required_setting_fields
    adapter = RedmineAiHelper::ChatChannel::BaseAdapter.adapters[channel_type]
    adapter ? adapter.required_setting_fields : []
  end

  # Validates that the adapter's required fields are present when the
  # integration is enabled. Tokens themselves never appear in error messages.
  def required_fields_present_when_enabled
    return unless enabled?

    required_setting_fields.each do |field|
      errors.add(field, :blank) if send(field).blank?
    end
  end

  # Replace all characters after the 4th with "*".
  def mask_token(token)
    return token if token.blank? || token.length <= 4

    masked = token.dup
    masked[4..-1] = "*" * (masked.length - 4)
    masked
  end
end
