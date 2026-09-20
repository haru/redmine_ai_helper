class AddUniqueIndexToAiHelperProjectSettingsProjectId < ActiveRecord::Migration[7.2]
  def change
    add_index :ai_helper_project_settings, :project_id, unique: true
  end
end
