# frozen_string_literal: true

# Adds the "register all projects" flag to the global AI Helper settings.
# Default true preserves the pre-feature behavior (all ai_helper-module
# projects are registered) for existing rows.
class AddVectorRegisterAllProjectsToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :vector_register_all_projects, :boolean, null: false, default: true
  end
end
