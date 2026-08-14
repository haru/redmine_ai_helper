# frozen_string_literal: true

# Adds the allowed organization (tenant) identifier to the chat adapter
# settings. Only the Microsoft Teams adapter declares it as a required field;
# rows of adapters that do not use it keep the column null.
class AddTenantIdToAiHelperChatAdapterSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_chat_adapter_settings, :tenant_id, :string
  end
end
