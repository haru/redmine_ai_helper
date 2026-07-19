# frozen_string_literal: true

# Per-adapter settings for external chat tool integrations. One row per
# adapter (channel_type, e.g. "slack"), holding the enable flag, credentials,
# and the default project for direct message conversations. Follows the same
# pattern as ai_helper_model_profiles: adding a new adapter never changes the
# schema.
class CreateAiHelperChatAdapterSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_chat_adapter_settings do |t|
      t.string :channel_type, null: false
      t.boolean :enabled, null: false, default: false
      t.string :app_token
      t.string :bot_token
      # projects.id is a signed int in Redmine core, so use :integer to keep the
      # foreign key valid on MySQL.
      t.integer :dm_default_project_id
      t.timestamps
    end

    add_index :ai_helper_chat_adapter_settings, :channel_type, unique: true
    add_foreign_key :ai_helper_chat_adapter_settings, :projects,
                    column: :dm_default_project_id, on_delete: :nullify
  end
end
