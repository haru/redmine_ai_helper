# frozen_string_literal: true

# Admin-only CRUD for channel-to-project bindings of external chat tools.
# Managed from the channels tab of the AI helper settings screen.
class AiHelperChannelBindingsController < ApplicationController
  layout "admin"

  before_action :require_admin
  self.main_menu = false

  # Create a binding and return to the channels tab
  def create
    binding = AiHelperChannelBinding.new(binding_params)
    if binding.save
      flash[:notice] = l(:notice_successful_create)
    else
      flash[:error] = binding.errors.full_messages.join(", ")
    end
    redirect_to_channels_tab
  end

  # Delete a binding and return to the channels tab
  def destroy
    AiHelperChannelBinding.find(params[:id]).destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_channels_tab
  end

  private

  # Permitted binding attributes from the add form
  def binding_params
    params.require(:ai_helper_channel_binding).permit(:channel_type, :channel_id, :channel_name, :project_id)
  end

  # All binding actions return to the channels tab of the settings screen
  def redirect_to_channels_tab
    redirect_to ai_helper_setting_path(tab: "channels")
  end
end
