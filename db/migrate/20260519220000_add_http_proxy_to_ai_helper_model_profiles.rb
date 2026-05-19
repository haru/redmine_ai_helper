class AddHttpProxyToAiHelperModelProfiles < ActiveRecord::Migration[6.1]
  def change
    add_column :ai_helper_model_profiles, :http_proxy, :string
  end
end
