# frozen_string_literal: true

# AiHelperSetting Controller for managing AI Helper settings
class AiHelperSettingsController < ApplicationController
  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_admin, :find_setting
  self.main_menu = false

  include AiHelperSettingsHelper

  # Display the settings page
  def index
    @selected_tab = params[:tab].presence
  end

  # Update the settings
  def update
    @setting.safe_attributes = params[:ai_helper_setting]
    @chat_adapter_settings = chat_adapter_settings_from_params
    setting_saved = @setting.save
    adapters_saved = @chat_adapter_settings.values.map(&:save).all?
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

  # Find or create the AI Helper setting and load model profiles
  def find_setting
    @setting = AiHelperSetting.find_or_create
    @model_profiles = AiHelperModelProfile.order(:name)
    @ai_helper_projects = Project.joins(:enabled_modules).where(enabled_modules: { name: "ai_helper" }).order(:name)
    @channel_bindings = AiHelperChannelBinding.includes(:project).order(:channel_type, :channel_id)
  end

  # Builds adapter setting records from the channels tab params, keyed by
  # channel_type. Only registered adapters are accepted.
  # @return [Hash{String => AiHelperChatAdapterSetting}]
  def chat_adapter_settings_from_params
    submitted = params[:chat_adapter_settings] || {}
    RedmineAiHelper::ChatChannel::BaseAdapter.adapters.keys.each_with_object({}) do |channel_type, hash|
      attrs = submitted[channel_type]
      next unless attrs

      setting = AiHelperChatAdapterSetting.for_channel(channel_type)
      setting.safe_attributes = attrs
      hash[channel_type] = setting
    end
  end
end
