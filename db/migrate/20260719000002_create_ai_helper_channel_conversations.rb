# frozen_string_literal: true

# Mapping between an external chat tool thread and an existing AI helper
# conversation. One thread maps to exactly one conversation (unique on
# channel_type + thread_key).
class CreateAiHelperChannelConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_channel_conversations do |t|
      t.string :channel_type, null: false
      t.string :thread_key, null: false
      t.integer :conversation_id, null: false
      t.timestamps
    end

    add_index :ai_helper_channel_conversations, [ :channel_type, :thread_key ],
              unique: true,
              name: "index_ai_helper_channel_conversations_unique"
    add_index :ai_helper_channel_conversations, :conversation_id
    add_foreign_key :ai_helper_channel_conversations, :ai_helper_conversations,
                    column: :conversation_id, on_delete: :cascade
  end
end
