# frozen_string_literal: true

class ExpandHealthReportMetricsColumn < ActiveRecord::Migration[7.2]
  MYSQL_LONGTEXT_LIMIT = 4_294_967_295

  def up
    return unless mysql_adapter?

    change_column :ai_helper_health_reports, :metrics, :text, limit: MYSQL_LONGTEXT_LIMIT
  end

  def down
    return unless mysql_adapter?

    change_column :ai_helper_health_reports, :metrics, :text
  end

  private

  def mysql_adapter?
    connection.adapter_name.downcase.include?("mysql")
  end
end
