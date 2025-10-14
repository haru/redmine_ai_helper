class RemovePeriodColumnsFromHealthReports < ActiveRecord::Migration[7.2]
  def change
    # Remove columns related to report period tracking
    remove_column :ai_helper_health_reports, :report_parameters, :text
    remove_column :ai_helper_health_reports, :version_id, :integer
    remove_column :ai_helper_health_reports, :start_date, :date
    remove_column :ai_helper_health_reports, :end_date, :date
  end
end
