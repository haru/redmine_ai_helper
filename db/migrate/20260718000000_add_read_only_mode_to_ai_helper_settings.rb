# frozen_string_literal: true
class AddReadOnlyModeToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :read_only_mode, :boolean, null: false, default: false
  end
end
