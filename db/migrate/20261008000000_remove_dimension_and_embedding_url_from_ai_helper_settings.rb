# frozen_string_literal: true

# Removes the unused dimension and embedding_url columns from ai_helper_settings.
# The embedding dimension is detected automatically and the embedding endpoint
# follows the model profile, so neither value was read anywhere.
class RemoveDimensionAndEmbeddingUrlFromAiHelperSettings < ActiveRecord::Migration[7.2]
  def change
    remove_column :ai_helper_settings, :dimension, :integer
    remove_column :ai_helper_settings, :embedding_url, :string
  end
end
