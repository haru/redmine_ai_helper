# frozen_string_literal: true
class AddMcpServerEnabledToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :mcp_server_enabled, :boolean, null: false, default: false
  end
end
