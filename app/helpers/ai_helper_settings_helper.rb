# frozen_string_literal: true

# Helper methods for AI Helper global settings views
module AiHelperSettingsHelper
  ERROR_ATTRIBUTE_TO_TAB = {
    "attachment_max_size_mb" => "general",
    "think_model_profile_id" => "model",
    "vector_search_uri" => "vector",
    "vector_model_profile_id" => "vector"
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
      }
    ].freeze
  end

  # Maps an error attribute name to its owning tab name.
  #
  # @param attribute [String] the attribute name with validation error
  # @return [String, nil] the tab name, or nil if no mapping exists
  def ai_helper_settings_tab_for_error(attribute)
    ERROR_ATTRIBUTE_TO_TAB[attribute]
  end

  # Determines the selected tab based on validation errors and the params[:tab] fallback.
  #
  # @param error_attributes [Array<String>] attribute names with validation errors
  # @param params_tab [String, nil] the value of params[:tab]
  # @return [String, nil] the selected tab name, or nil to use render_tabs default
  def ai_helper_settings_selected_tab(error_attributes, params_tab)
    error_attributes.each do |attr|
      found = ai_helper_settings_tab_for_error(attr)
      return found if found
    end
    params_tab
  end
end
