# frozen_string_literal: true
class AddVectorModelProfileToAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_settings, :use_vector_model_profile, :boolean, null: false, default: false
    add_column :ai_helper_settings, :vector_model_profile_id, :integer
  end
end
