class AddThinkModelToAiHelperSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :ai_helper_settings, :use_think_model, :boolean, default: false
    add_column :ai_helper_settings, :think_model_profile_id, :integer
  end
end
