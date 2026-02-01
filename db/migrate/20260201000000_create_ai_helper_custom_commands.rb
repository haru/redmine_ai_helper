class CreateAiHelperCustomCommands < ActiveRecord::Migration[5.2]
  def change
    create_table :ai_helper_custom_commands do |t|
      t.string :name, limit: 50, null: false
      t.text :prompt, null: false
      t.integer :command_type, null: false, default: 0
      t.integer :user_scope, default: 0
      t.references :project, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
