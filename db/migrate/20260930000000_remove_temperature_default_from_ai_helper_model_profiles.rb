# frozen_string_literal: true

# Make the temperature column optional: remove the 0.5 default so that new
# profiles start with an unset (NULL) temperature. Existing rows keep their
# values (change_column_default does not touch existing data).
class RemoveTemperatureDefaultFromAiHelperModelProfiles < ActiveRecord::Migration[7.2]
  def change
    change_column_default :ai_helper_model_profiles, :temperature, from: 0.5, to: nil
  end
end
