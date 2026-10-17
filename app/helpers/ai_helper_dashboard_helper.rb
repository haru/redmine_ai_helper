# Helper methods shared by the AI Helper dashboard views.
module AiHelperDashboardHelper
  include AiHelperHelper

  require "redmine_ai_helper/health_report_chart/resolver"
  require "redmine_ai_helper/health_report_chart/scanner"

  # Render a stored health report body as Markdown HTML, independent of the
  # Redmine text formatting setting, and linkify bare issue references.
  # Chart directive lines are resolved from the report's stored metrics and
  # replaced by the chart partial's HTML. A body without chart directives
  # returns exactly the same HTML as the plain Markdown pipeline (SC-002).
  # @param text [String] The Markdown source text of the report body.
  # @param report [AiHelperHealthReport, nil] The report the body belongs to;
  #   nil means the body is rendered without stored metrics.
  # @return [ActiveSupport::SafeBuffer] Sanitized HTML with issue links and charts.
  # @raise [RuntimeError] when a marker paragraph is lost during rendering.
  def render_health_report_markdown(text, report:)
    parts = RedmineAiHelper::HealthReportChart::Scanner.split(text.to_s)
    return linkify_issue_references(md_to_html(text)) unless parts.any?(RedmineAiHelper::HealthReportChart::Directive)

    resolver = RedmineAiHelper::HealthReportChart::Resolver.new(report&.metrics)
    directives = []
    markers = []
    marked = parts.map do |part|
      case part
      when RedmineAiHelper::HealthReportChart::Directive
        directives << part
        marker = chart_marker
        markers << marker
        "\n\n#{marker}\n\n"
      when String
        part
      else
        raise ArgumentError, "expected a String or a Directive, got #{part.class}"
      end
    end.join

    html = linkify_issue_references(md_to_html(marked)).to_s
    directives.each_with_index do |directive, index|
      marker = markers[index]
      replaced = false
      html = html.sub("<p>#{marker}</p>") { replaced = true; chart_html(directive, resolver) }
      raise "Chart marker paragraph was not rendered in the report body" unless replaced
    end
    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  # Render one chart directive position as the chart partial's HTML.
  # @param directive [RedmineAiHelper::HealthReportChart::Directive] the parsed directive
  # @param resolver [RedmineAiHelper::HealthReportChart::Resolver] resolver built
  #   from the report's stored metrics
  # @return [String] the partial's HTML for the Chart or Unavailable state
  # @raise [ArgumentError] when the resolver returns neither a Chart nor an Unavailable
  def chart_html(directive, resolver)
    resolved = resolver.resolve(directive)
    case resolved
    when RedmineAiHelper::HealthReportChart::Chart, RedmineAiHelper::HealthReportChart::Unavailable
      render "ai_helper/project/health_report_chart", resolved: resolved
    else
      raise ArgumentError, "expected a Chart or an Unavailable, got #{resolved.class}"
    end
  end

  # An unpredictable paragraph marker made of lowercase letters and digits
  # only, so it survives the Markdown pipeline untouched (no # or markup).
  # @return [String]
  def chart_marker
    "aihelperchart#{SecureRandom.hex(12)}"
  end

  # Emit the Chart.js classic asset into the page head exactly once, but only
  # when Redmine's importmap does not pin chart.js: Redmine 6.1.x has an
  # importmap without the pin and Redmine 6.0.x has no importmap at all. On
  # Redmine 7 the chart.js importmap pin is used by the dynamic import
  # instead (R-007).
  # @return [void]
  def ai_helper_chart_heads
    return if @ai_helper_chart_heads_included # rubocop:disable Rails/HelperInstanceVariable
    return if Rails.application.respond_to?(:importmap) && Rails.application.importmap.packages.key?("chart.js")

    content_for :header_tags do
      javascript_include_tag "chart.min"
    end
    @ai_helper_chart_heads_included = true # rubocop:disable Rails/HelperInstanceVariable
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
