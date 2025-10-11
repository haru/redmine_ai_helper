# frozen_string_literal: true
# Controller for performing CRUD operations on ModelProfile
class AiHelperModelProfilesController < ApplicationController
  layout "admin"
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

  # Find the model profile based on the provided ID
  def find_model_profile
    id = params[:id] # TODO: remove this line
    return if params[:id].blank?
    @model_profile = AiHelperModelProfile.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
