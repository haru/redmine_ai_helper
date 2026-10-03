# Helper methods shared by the AI Helper dashboard views.
module AiHelperDashboardHelper
  include AiHelperHelper

  # Render a stored health report body as Markdown HTML, independent of the
  # Redmine text formatting setting, and linkify bare issue references.
  # @param text [String] The Markdown source text of the report body.
  # @return [ActiveSupport::SafeBuffer] Sanitized HTML with issue links.
  def render_health_report_markdown(text)
    linkify_issue_references(md_to_html(text))
  end

  # Build the one-line Markdown quote that marks an edited report in exports.
  # @param report [AiHelperHealthReport] The report being exported.
  # @return [String, nil] The quote line, or nil when the report is unedited.
  def health_report_edit_notice_text(report)
    return nil unless report.edited?

    detail = l("ai_helper.health_report_edit.edited_by_on_html",
               user: report.last_edited_by.name,
               time: format_time(report.last_edited_on))
    "> #{l("ai_helper.health_report_edit.edited")}: #{detail}"
  end

  # Emit the CommonMark jsToolbar assets into the page head exactly once,
  # independent of the Redmine text formatting setting (health reports are
  # always Markdown).
  # @return [void]
  def ai_helper_markdown_toolbar_heads
    return if @ai_helper_markdown_toolbar_heads_included # rubocop:disable Rails/HelperInstanceVariable

    toolbar_language_options = User.current&.pref&.toolbar_language_options
    langs = toolbar_language_options.nil? ? UserPreference::DEFAULT_TOOLBAR_LANGUAGE_OPTIONS : toolbar_language_options.split(",")
    content_for :header_tags do
      javascript_include_tag("jstoolbar/jstoolbar") +
        javascript_include_tag("jstoolbar/common_mark") +
        javascript_include_tag("jstoolbar/lang/jstoolbar-#{current_language.to_s.downcase}") +
        javascript_tag(
          "var wikiImageMimeTypes = #{Redmine::MimeType.by_type("image").to_json};" \
          "var userHlLanguages = #{langs.to_json};"
        ) +
        stylesheet_link_tag("jstoolbar")
    end
    @ai_helper_markdown_toolbar_heads_included = true # rubocop:disable Rails/HelperInstanceVariable
  end

  # Build the list of dashboard tabs that are rendered in the UI.
  # @return [Array<Hash>] tab descriptors for the dashboard view.
  def ai_helper_dashboard_tabs
    tabs = [
      { name: "health_report", action: :health_report, label: "ai_helper.project_health.title", partial: "ai_helper_dashboard/health_report" },
      { name: "custom_commands", action: :custom_commands, label: "ai_helper.custom_commands.label.title", partial: "ai_helper_dashboard/custom_commands" }
    ]

    if @project && User.current.allowed_to?(:settings_ai_helper, @project) # rubocop:disable Rails/HelperInstanceVariable
      tabs << { name: "settings", action: :settings, label: :label_settings, partial: "ai_helper_project_settings/show" }
    end

    tabs
  end
end
