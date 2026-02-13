class AddDescriptionToAiHelperCustomCommands < ActiveRecord::Migration[5.2]
  def change
    add_column :ai_helper_custom_commands, :description, :string, limit: 200
  end
end
