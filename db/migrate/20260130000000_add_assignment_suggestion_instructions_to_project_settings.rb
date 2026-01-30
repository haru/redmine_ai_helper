class AddAssignmentSuggestionInstructionsToProjectSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_project_settings, :assignment_suggestion_instructions, :text
  end
end
