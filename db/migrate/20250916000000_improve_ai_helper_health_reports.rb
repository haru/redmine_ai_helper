class ImproveAiHelperHealthReports < ActiveRecord::Migration[7.2]
  def change

    # Add indexes
    add_index :ai_helper_health_reports, :project_id unless index_exists?(:ai_helper_health_reports, :project_id)
    add_index :ai_helper_health_reports, :user_id unless index_exists?(:ai_helper_health_reports, :user_id)
    add_index :ai_helper_health_reports, [:project_id, :created_at] unless index_exists?(:ai_helper_health_reports, [:project_id, :created_at])

    # Add foreign key constraints if they don't exist
    unless foreign_key_exists?(:ai_helper_health_reports, :projects)
      add_foreign_key :ai_helper_health_reports, :projects, column: :project_id
    end
    unless foreign_key_exists?(:ai_helper_health_reports, :users)
      add_foreign_key :ai_helper_health_reports, :users, column: :user_id
    end

    # Add columns for report parameters
    add_column :ai_helper_health_reports, :report_parameters, :text unless column_exists?(:ai_helper_health_reports, :report_parameters)
    add_column :ai_helper_health_reports, :version_id, :integer unless column_exists?(:ai_helper_health_reports, :version_id)
    add_column :ai_helper_health_reports, :start_date, :date unless column_exists?(:ai_helper_health_reports, :start_date)
    add_column :ai_helper_health_reports, :end_date, :date unless column_exists?(:ai_helper_health_reports, :end_date)
  end
end
