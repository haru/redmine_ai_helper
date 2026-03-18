# frozen_string_literal: true
# Controller for performing CRUD operations on ModelProfile
class AiHelperModelProfilesController < ApplicationController
  include RedmineAiHelper::Logger

  layout "admin"

  protect_from_forgery with: :exception

  before_action :require_admin
  before_action :find_model_profile, only: [:show, :edit, :update, :destroy]
  self.main_menu = false

  # Placeholder value used to mask the actual access key in forms
  # to prevent accidental exposure of sensitive API keys.
  # When this value is submitted, the original access key is preserved.
  DUMMY_ACCESS_KEY = "___DUMMY_ACCESS_KEY___"

  # Display the model profile
  def show
    render partial: "ai_helper_model_profiles/show"
  end

  # Display the form for creating a new model profile
  def new
    @title = l("ai_helper.model_profiles.create_profile_title")
    @model_profile = AiHelperModelProfile.new
  end

  # Create a new model profile
  def create
    @model_profile = AiHelperModelProfile.new
    @model_profile.safe_attributes = params[:ai_helper_model_profile]
    if @model_profile.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to ai_helper_setting_path
    else
      render action: :new
    end
  end

  # Display the form for editing an existing model profile
  def edit
  end

  # Update an existing model profile
  def update
    original_access_key = @model_profile.access_key
    @model_profile.safe_attributes = params[:ai_helper_model_profile]
    @model_profile.access_key = original_access_key if @model_profile.access_key == DUMMY_ACCESS_KEY
    if @model_profile.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to ai_helper_setting_path
    else
      render action: :edit
    end
  end

  # Test the LLM connection using the current form parameters
  def test_connection
    temp_profile = AiHelperModelProfile.new
    temp_profile.safe_attributes = params[:ai_helper_model_profile]

    if temp_profile.access_key == DUMMY_ACCESS_KEY
      if params[:id].present?
        original = AiHelperModelProfile.find(params[:id])
        temp_profile.access_key = original.access_key
      else
        render json: { success: false, error: l("ai_helper.model_profiles.messages.access_key_required") }, status: :unprocessable_entity
        return
      end
    end

    temp_profile.temperature ||= 1.0

    unless temp_profile.llm_type.present? && temp_profile.llm_model.present? &&
           (temp_profile.access_key.present? || !temp_profile.access_key_required?) &&
           (temp_profile.base_uri.present? || !temp_profile.base_uri_required?)
      render json: { success: false, error: l("ai_helper.model_profiles.messages.required_fields_missing") }, status: :unprocessable_entity
      return
    end

    provider = RedmineAiHelper::LlmProvider.provider_for_profile(temp_profile)
    chat = provider.create_chat
    chat.ask("hi")
    render json: { success: true }
  rescue => e
    ai_helper_logger.error("LLM connection test failed: #{e.message}")
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Delete an existing model profile
  def destroy
    if @model_profile.destroy
      flash[:notice] = l(:notice_successful_delete)
      redirect_to ai_helper_setting_path
    else
      flash[:error] = l(:error_failed_delete)
      redirect_to ai_helper_setting_path
    end
  rescue ActiveRecord::RecordNotFound
    render_404
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

  # Find the model profile based on the provided ID
  def find_model_profile
    id = params[:id] # TODO: remove this line
    return if params[:id].blank?
    @model_profile = AiHelperModelProfile.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
