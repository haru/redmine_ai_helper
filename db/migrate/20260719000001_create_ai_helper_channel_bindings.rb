# frozen_string_literal: true

# Binding between an external chat tool channel and a Redmine project.
# One channel maps to exactly one project (unique on channel_type + channel_id).
class CreateAiHelperChannelBindings < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_channel_bindings do |t|
      t.string :channel_type, null: false
      t.string :channel_id, null: false
      t.string :channel_name
      # projects.id is a signed int in Redmine core, so use :integer to keep the
      # foreign key valid on MySQL.
      t.integer :project_id, null: false
      t.timestamps
    end

    add_index :ai_helper_channel_bindings, [ :channel_type, :channel_id ],
              unique: true,
              name: "index_ai_helper_channel_bindings_unique"
    add_index :ai_helper_channel_bindings, :project_id
    add_foreign_key :ai_helper_channel_bindings, :projects, on_delete: :cascade
  end
end
