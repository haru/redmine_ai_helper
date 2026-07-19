# frozen_string_literal: true

# Adds the service account (execution account) to the chat adapter settings.
# All questions from external chat tools are processed under this Redmine
# user's permissions; speakers are not mapped to Redmine users.
class AddRedmineUserIdToAiHelperChatAdapterSettings < ActiveRecord::Migration[7.2]
  def change
    # users.id is a signed int in Redmine core, so use :integer to keep the
    # foreign key valid on MySQL.
    add_column :ai_helper_chat_adapter_settings, :redmine_user_id, :integer
    add_foreign_key :ai_helper_chat_adapter_settings, :users,
                    column: :redmine_user_id, on_delete: :nullify
  end
end
