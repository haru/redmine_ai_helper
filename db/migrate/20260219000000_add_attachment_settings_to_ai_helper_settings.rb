class AddAttachmentSettingsToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :attachment_send_enabled, :boolean, default: false, null: false
    add_column :ai_helper_settings, :attachment_max_size_mb, :integer, default: 3, null: false
  end
end
