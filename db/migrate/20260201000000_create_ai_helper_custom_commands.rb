class CreateAiHelperCustomCommands < ActiveRecord::Migration[5.2]
  def change
    create_table :ai_helper_custom_commands do |t|
      t.string :name, limit: 50, null: false
      t.text :prompt, null: false
      t.integer :command_type, null: false, default: 0
      t.integer :user_scope, default: 0
      t.integer :project_id
      t.integer :user_id, null: false

      t.timestamps
    end

    add_index :ai_helper_custom_commands, :project_id
    add_index :ai_helper_custom_commands, :user_id
    add_foreign_key :ai_helper_custom_commands, :projects
    add_foreign_key :ai_helper_custom_commands, :users
  end
end
