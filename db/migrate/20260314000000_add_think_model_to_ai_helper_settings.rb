class AddThinkModelToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :use_think_model, :boolean, null: false, default: false
    add_column :ai_helper_settings, :think_model_profile_id, :integer
  end
end
