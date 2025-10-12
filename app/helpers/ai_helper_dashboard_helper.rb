# Helper methods shared by the AI Helper dashboard views.
module AiHelperDashboardHelper
  # Build the list of dashboard tabs that are rendered in the UI.
  # @return [Array<Hash>] tab descriptors for the dashboard view.
  def ai_helper_dashboard_tabs
    tabs = [
      { name: "health_report", action: :health_report, label: "ai_helper.project_health.title", partial: "ai_helper_dashboard/health_report" },
      { name: "settings", action: :settings, label: :label_settings, partial: "ai_helper_project_settings/show" },
    ]

    tabs
  end
end
