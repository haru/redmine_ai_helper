# frozen_string_literal: true

# Adds the per-profile prompt caching switch. It only takes effect for
# Anthropic profiles; existing profiles default to enabled.
class AddPromptCachingEnabledToAiHelperModelProfiles < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_model_profiles, :prompt_caching_enabled, :boolean, default: true, null: false
  end
end
