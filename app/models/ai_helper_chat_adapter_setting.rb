# frozen_string_literal: true

# Per-adapter settings for external chat tool integrations. One row per
# adapter (channel_type, e.g. "slack"). Follows the same pattern as
# AiHelperModelProfile: typed columns shared by all adapters, with per-adapter
# required fields declared by the adapter class itself.
class AiHelperChatAdapterSetting < ApplicationRecord
  include Redmine::SafeAttributes

  # The default project is the fallback context for direct messages and for
  # regular channels that have no channel binding. Stored in the existing
  # physical column dm_default_project_id (kept for backward compatibility);
  # the Ruby-layer name drops the "dm_" prefix because the meaning is no
  # longer limited to direct messages.
  belongs_to :default_project, class_name: "Project", foreign_key: "dm_default_project_id", inverse_of: false, optional: true
  belongs_to :redmine_user, class_name: "User", optional: true

  attr_accessor :redmine_user_name

  validates :channel_type, presence: true, uniqueness: true
  validate :required_fields_present_when_enabled
  validate :service_account_present_when_enabled
  validate :default_project_present_when_enabled
  validate :redmine_user_name_matches_existing_user

  safe_attributes "enabled", "app_token", "bot_token", "tenant_id", "default_project_id", "redmine_user_id", "redmine_user_name"

  # Reads the default project id from the physical dm_default_project_id column.
  # @return [Integer, nil]
  def default_project_id
    dm_default_project_id
  end

  # Writes the default project id to the physical dm_default_project_id column.
  # @param value [Integer, String, nil]
  def default_project_id=(value)
    self.dm_default_project_id = value
  end

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

  # The Redmine user all chat tool questions are executed as. Only an active
  # user qualifies: a locked or missing account disables the gateway rather
  # than silently running with stale permissions.
  # @return [User, nil]
  def service_account
    user = redmine_user
    user&.active? ? user : nil
  end

  # Whether this adapter's settings are substantively filled in: the record is
  # saved and all fields required to operate the integration (adapter tokens and
  # the execution account) are present. Used to decide whether the channel
  # bindings form should be shown — a bare, empty settings row is not enough.
  # @return [Boolean]
  def configured?
    return false unless persisted?
    return false if redmine_user_id.blank?

    required_setting_fields.all? { |field| send(field).present? }
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

  # Validates that the execution account is set when the integration is
  # enabled. The execution account is the permission boundary for everything
  # the gateway can do, so an enabled adapter must never run without one.
  def service_account_present_when_enabled
    return unless enabled?

    errors.add(:redmine_user_id, :blank) if redmine_user_id.blank?
  end

  # Validates that a default project is set when the integration is enabled.
  # An enabled adapter must resolve every message to a project (direct messages
  # and unbound channels fall back to the default project), so enabling without
  # one is rejected. A disabled adapter may be saved as a draft without it.
  def default_project_present_when_enabled
    return unless enabled?

    errors.add(:default_project_id, :blank) if default_project_id.blank?
  end

  # Validates that the submitted redmine_user_name corresponds to an actual
  # user record. When the form sends a non-matching name, the hidden
  # redmine_user_id will be blank — this catches the mismatch server-side.
  def redmine_user_name_matches_existing_user
    return if redmine_user_name.blank?
    return if redmine_user_id.present?

    errors.add(:redmine_user_name, :invalid)
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
