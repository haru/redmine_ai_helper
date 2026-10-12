# frozen_string_literal: true

# Adds the system-wide web search switch. Existing rows default to disabled.
class AddWebSearchEnabledToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :web_search_enabled, :boolean, default: false, null: false
  end
end
