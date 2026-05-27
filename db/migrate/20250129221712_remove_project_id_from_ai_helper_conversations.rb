class RemoveProjectIdFromAiHelperConversations < ActiveRecord::Migration[7.2]
  def change
    remove_column :ai_helper_conversations, :project_id, :integer
  end
end
