# frozen_string_literal: true

# Helper methods for AI Helper global settings views
module AiHelperSettingsHelper
  # Maps a setting attribute name to the tab that should be selected when the
  # attribute has a validation error, so the user is shown the failing field.
  ERROR_ATTRIBUTE_TO_TAB = {
    attachment_max_size_mb: "general",
    think_model_profile_id: "model",
    vector_search_uri: "vector",
    vector_model_profile_id: "vector"
  }.freeze

  # Returns tab definitions for the settings page.
  # Each tab hash contains :name, :partial, :label, and :f (form builder).
  #
  # @param f [ActionView::Helpers::FormBuilder] the form builder for the settings form
  # @return [Array<Hash>] array of tab definition hashes
  def ai_helper_settings_tabs(f)
    [
      {
        name: "general",
        partial: "ai_helper_settings/general_tab",
        label: :"ai_helper.settings.tab_general",
        f: f
      },
      {
        name: "model",
        partial: "ai_helper_settings/model_tab",
        label: :"ai_helper.settings.tab_model",
        f: f
      },
      {
        name: "vector",
        partial: "ai_helper_settings/vector_tab",
        label: :"ai_helper.settings.tab_vector",
        f: f
      },
      {
        name: "channels",
        partial: "ai_helper_settings/channels_tab",
        label: :"ai_helper.settings.tab_channels",
        f: f
      }
    ]
  end

  # Returns the adapter setting record to render for the given channel_type,
  # preferring the (possibly invalid) record built from submitted params so
  # validation errors and entered values survive a re-render.
  #
  # @param channel_type [String] adapter identifier (e.g. "slack")
  # @param submitted [Hash{String => AiHelperChatAdapterSetting}, nil] records built from params
  # @return [AiHelperChatAdapterSetting]
  def ai_helper_chat_adapter_setting(channel_type, submitted)
    (submitted || {})[channel_type] || AiHelperChatAdapterSetting.for_channel(channel_type)
  end

  # Display label for a chat adapter, resolved from the locale file with the
  # humanized channel_type as fallback.
  #
  # @param channel_type [String] adapter identifier (e.g. "slack")
  # @return [String]
  def ai_helper_chat_adapter_label(channel_type)
    t("ai_helper.chat_channel.adapters.#{channel_type}", default: channel_type.humanize)
  end

  # Maps an error attribute name to its owning tab name.
  #
  # @param attribute [Symbol] the attribute name with validation error
  # @return [String, nil] the tab name, or nil if no mapping exists
  def ai_helper_settings_tab_for_error(attribute)
    ERROR_ATTRIBUTE_TO_TAB[attribute]
  end

  # Determines the selected tab based on validation errors and the params[:tab] fallback.
  #
  # @param error_attributes [Array<Symbol>] attribute names with validation errors
  # @param params_tab [String, nil] the value of params[:tab]
  # @return [String, nil] the selected tab name, or nil to use render_tabs default
  def ai_helper_settings_selected_tab(error_attributes, params_tab)
    error_attributes.each do |attr|
      found = ai_helper_settings_tab_for_error(attr)
      return found if found
    end
    params_tab
  end

  # Returns options for model profile select fields.
  #
  # @param profiles [ActiveRecord::Relation] collection of model profiles
  # @return [Array<Array<String, Integer>>] array of [display_name, id] pairs
  def ai_helper_model_profile_options(profiles)
    profiles.map { |p| [ p.display_name, p.id ] }
  end
end
