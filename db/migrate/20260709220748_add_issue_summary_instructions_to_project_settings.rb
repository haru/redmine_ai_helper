class AddIssueSummaryInstructionsToProjectSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_project_settings, :issue_summary_instructions, :text
  end
end
