# frozen_string_literal: true

class AddEditColumnsToAiHelperHealthReports < ActiveRecord::Migration[7.2]
  def change
    add_column :ai_helper_health_reports, :original_health_report, :text
    add_column :ai_helper_health_reports, :last_edited_by_id, :integer
    add_column :ai_helper_health_reports, :last_edited_on, :datetime
    add_column :ai_helper_health_reports, :lock_version, :integer, null: false, default: 0
    add_index :ai_helper_health_reports, :last_edited_by_id
    add_foreign_key :ai_helper_health_reports, :users, column: :last_edited_by_id
  end
end
