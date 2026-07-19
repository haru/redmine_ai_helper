# frozen_string_literal: true

# AiHelperSetting Controller for managing AI Helper settings
class AiHelperSettingsController < ApplicationController
  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_admin, :find_setting
  self.main_menu = false

  include AiHelperSettingsHelper

  # Placeholder value rendered in token fields when a token is already
  # stored, so the raw value never reaches the HTML source (same approach
  # as AiHelperModelProfilesController::DUMMY_ACCESS_KEY). When this value
  # is submitted, the controller keeps the existing token unchanged.
  DUMMY_TOKEN = "___DUMMY_TOKEN___"

  # Display the settings page
  def index
    @selected_tab = params[:tab].presence
  end

  # Update the settings. The global setting and every adapter setting are
  # persisted atomically: if any of them is invalid, none is kept, so the
  # page never re-renders with only half of the changes committed.
  def update
    @setting.safe_attributes = params[:ai_helper_setting]
    @chat_adapter_settings = chat_adapter_settings_from_params

    setting_saved = nil
    adapters_saved = nil
    AiHelperSetting.transaction do
      setting_saved = @setting.save
      adapters_saved = @chat_adapter_settings.values.map(&:save).all?
      raise ActiveRecord::Rollback unless setting_saved && adapters_saved
    end

    if setting_saved && adapters_saved
      flash[:notice] = l(:notice_successful_update)
      redirect_to action: :index, tab: params[:tab].presence
    else
      @selected_tab = if adapters_saved
          ai_helper_settings_selected_tab(
            @setting.errors.attribute_names,
            params[:tab].presence
          )
      else
          "channels"
      end
      render action: :index
    end
  end

  private

  # Always enforce CSRF verification for this controller.
  # Overrides Redmine's ApplicationController which conditionally skips
  # verification for API requests. This controller does not serve API requests.
  def verify_authenticity_token
    unless verified_request?
      handle_unverified_request
    end
  end

  # Always handle unverified requests by returning 422.
  # Overrides Redmine's version which skips handling for API-format requests.
  def handle_unverified_request
    cookies.delete(autologin_cookie_name)
    self.logged_user = nil
    set_localization
    render_error status: 422, message: l(:error_invalid_authenticity_token)
  end

  # Find or create the AI Helper setting and load all settings data
  # (model profiles, projects, channel bindings, and active users).
  def find_setting
    @setting = AiHelperSetting.find_or_create
    @model_profiles = AiHelperModelProfile.order(:name)
    @ai_helper_projects = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).order(:name)
    @channel_bindings_by_type = AiHelperChannelBinding.includes(:project)
                                                      .order(:channel_type, :channel_id)
                                                      .group_by(&:channel_type)
    @ai_helper_users = User.active.sorted
  end

  # Builds adapter setting records from the channels tab params, keyed by
  # channel_type. Only registered adapters are accepted. Token fields that
  # come back unchanged from the form (DUMMY_TOKEN) are preserved as-is so
  # the stored secret is never round-tripped through the browser.
  # @return [Hash{String => AiHelperChatAdapterSetting}]
  def chat_adapter_settings_from_params
    submitted = params[:chat_adapter_settings] || {}
    RedmineAiHelper::ChatChannel::BaseAdapter.adapters.keys.each_with_object({}) do |channel_type, hash|
      attrs = submitted[channel_type]
      next unless attrs

      setting = AiHelperChatAdapterSetting.for_channel(channel_type)
      preserve_unchanged_tokens!(setting, attrs)
      setting.safe_attributes = attrs
      hash[channel_type] = setting
    end
  end

  # Replaces DUMMY_TOKEN submissions with the value currently stored so the
  # operator does not have to re-enter a secret to keep it.
  def preserve_unchanged_tokens!(setting, attrs)
    %w[app_token bot_token].each do |field|
      next unless attrs[field] == DUMMY_TOKEN

      attrs[field] = setting.send(field)
    end
  end
end
