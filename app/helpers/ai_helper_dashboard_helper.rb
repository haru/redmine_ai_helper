module AiHelperDashboardHelper
  def ai_helper_dashboard_tabs
    tabs = [
      { name: "overview", action: :overview, label: :label_overview, partial: "ai_helper_dashboard/overview" },
      { name: "settings", action: :settings, label: :label_settings, partial: "ai_helper_project_settings/show" },
    ]

    tabs
  end
end
