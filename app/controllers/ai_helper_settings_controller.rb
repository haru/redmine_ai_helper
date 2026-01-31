# frozen_string_literal: true
# AiHelperSetting Controller for managing AI Helper settings
class AiHelperSettingsController < ApplicationController
  layout "admin"

  protect_from_forgery

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

  # Find or create the AI Helper setting and load model profiles
  def find_setting
    @setting = AiHelperSetting.find_or_create
    @model_profiles = AiHelperModelProfile.order(:name)
  end
end
