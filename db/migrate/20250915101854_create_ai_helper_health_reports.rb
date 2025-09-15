class CreateAiHelperHealthReports < ActiveRecord::Migration[7.2]
  def change
    create_table :ai_helper_health_reports do |t|
      t.integer :project_id
      t.integer :user_id
      t.text :health_report
      t.text :metrics
      t.time :created_at
      t.time :updated_at
    end
  end
end
