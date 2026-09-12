# frozen_string_literal: true

class AddAllProjectsScopeToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :all_projects_scope, :boolean, null: false, default: false
  end
end
