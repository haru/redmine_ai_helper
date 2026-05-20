class AddHttpProxyToAiHelperModelProfiles < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_model_profiles, :http_proxy, :string
  end
end
