# frozen_string_literal: true

# Adds the import cursor to channel conversations: the external message id of
# the most recent mention whose surrounding messages were imported. NULL means
# nothing has been imported for the conversation yet. No index is added because
# the column is only ever read from a row already fetched by its primary key or
# the channel_type/thread_key unique index.
class AddLastImportedMessageKeyToAiHelperChannelConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_channel_conversations, :last_imported_message_key, :string
  end
end
