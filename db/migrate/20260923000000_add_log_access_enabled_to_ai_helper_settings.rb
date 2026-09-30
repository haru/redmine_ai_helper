# frozen_string_literal: true

class AddLogAccessEnabledToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :log_access_enabled, :boolean, null: false, default: false
  end
end
