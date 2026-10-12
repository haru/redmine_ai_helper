# frozen_string_literal: true

# Stores the web search sources (JSON) of an assistant answer. NULL when the
# answer has no sources, including every answer created before this column.
class AddCitationsToAiHelperMessages < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_messages, :citations, :text
  end
end
