# frozen_string_literal: true

class AddSendUserIdEnabledToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :send_user_id_enabled, :boolean, null: false, default: false
  end
end
