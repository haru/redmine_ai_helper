# frozen_string_literal: true
# AiHelperSetting Controller for managing AI Helper settings
class AiHelperSettingsController < ApplicationController
  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_admin, :find_setting
  self.main_menu = false

  # Display the settings page
  def index
  end

  # Update the settings
  def update
    @setting.safe_attributes = params[:ai_helper_setting]
    if @setting.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to action: :index
    else
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
  end
end
