# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperDashboardHelperTest < ActionView::TestCase
  include AiHelperHelper
  include AiHelperDashboardHelper
  include Redmine::I18n

  context "render_health_report_markdown" do
    setup do
      @original_text_formatting = Setting.text_formatting
    end

    teardown do
      Setting.text_formatting = @original_text_formatting
    end

    [ "textile", "common_mark", "" ].each do |formatting|
      should "render Markdown regardless of the #{formatting.inspect} text formatting setting" do
        Setting.text_formatting = formatting

        html = render_health_report_markdown("# Heading\n\n**bold** text", report: nil)

        assert_includes html, "<h1>Heading</h1>"
        assert_includes html, "<strong>bold</strong>"
      end
    end

    should "linkify bare issue references like the chat rendering does" do
      html = render_health_report_markdown("See #1234 in the report", report: nil)

      assert_includes html, %(<a href="/issues/1234">#1234</a>)
    end

    should "render report tables with the standard list class" do
      html = render_health_report_markdown("| col |\n|-----|\n| See #123 |", report: nil)

      assert_includes html, %(<table class="list">)
      assert_includes html, %(<a href="/issues/123">#123</a>)
    end

    should "sanitize script tags included in the body" do
      html = render_health_report_markdown("Safe text\n\n<script>alert('xss')</script>", report: nil)

      assert_no_match(%r{<script}, html)
    end
  end

  DIRECTIVE_BODY = "Before\n\n{{ai_helper_chart(status, version=12)}}\n\nAfter"

  METRICS_JSON = [
    {
      version_id: 12, version_name: "1.0.0",
      metrics: {
        issue_statistics: { by_status: { "New" => 3, "Closed" => 1 } }
      }
    }
  ].to_json

  context "render_health_report_markdown with chart directives" do
    setup do
      @original_text_formatting = Setting.text_formatting
      Setting.text_formatting = "textile"
      @report = AiHelperHealthReport.create!(
        project: Project.find(1), user: User.find(1),
        health_report: DIRECTIVE_BODY,
        metrics: METRICS_JSON
      )
    end

    teardown do
      Setting.text_formatting = @original_text_formatting
    end

    should "replace a chart directive line with the chart partial HTML" do
      html = render_health_report_markdown(@report.health_report, report: @report)

      assert_includes html, %(class="ai-helper-health-report-chart issue-report-graph")
      assert_includes html, %(role="img")
      assert_includes html, %(aria-label="Issues by Status - 1.0.0")
      assert_includes html, "<p>Before</p>"
      assert_includes html, "<p>After</p>"
      assert_not_includes html, "ai_helper_chart"

      json = extract_chart_json(html)
      assert_equal "doughnut", json["form"]
      assert_equal "Issues by Status - 1.0.0", json["title"]
      assert_equal [ "New (3)", "Closed (1)" ], json["labels"]
      assert_equal [ 3, 1 ], json["values"]
      assert_equal [ "rgba(255, 99, 132, 0.2)", "rgba(54, 162, 235, 0.2)" ], json["fillColors"]
      assert_equal [ "rgb(255, 99, 132)", "rgb(54, 162, 235)" ], json["borderColors"]
    end

    should "keep a body without chart directives unchanged" do
      text = "See #1234\n\n| col |\n|-----|\n| cell |"

      assert_equal linkify_issue_references(md_to_html(text)),
                   render_health_report_markdown(text, report: @report)
      assert_equal linkify_issue_references(md_to_html(text)),
                   render_health_report_markdown(text, report: nil)
    end

    should "keep a directive inside a fenced code block unchanged" do
      fenced = "```\n{{ai_helper_chart(status, version=12)}}\n```"

      assert_equal linkify_issue_references(md_to_html(fenced)),
                   render_health_report_markdown(fenced, report: @report)
    end

    should "render an unknown chart type as a warning paragraph" do
      body = "{{ai_helper_chart(burndown, version=12)}}"

      html = render_health_report_markdown(body, report: @report)

      assert_includes html, %(class="warning")
      assert_includes html, "Cannot draw the chart: "
      assert_includes html, "Unknown chart type"
      assert_not_includes html, "{{ai_helper_chart("
    end

    should "render a no_data chart as the title plus a nodata paragraph" do
      metrics = [ { version_id: 12, version_name: "1.0.0",
                    metrics: { issue_statistics: { by_status: { "New" => 0 } } } } ].to_json
      @report.update_columns(metrics: metrics)

      html = render_health_report_markdown(@report.health_report, report: @report)

      assert_includes html, "<strong>Issues by Status - 1.0.0</strong>"
      assert_includes html, %(class="nodata")
      assert_includes html, l(:label_no_data)
      assert_not_includes html, "<canvas"
    end

    should "report metrics_unavailable for a directive when the report is nil" do
      html = render_health_report_markdown(DIRECTIVE_BODY, report: nil)

      assert_includes html, %(class="warning")
      assert_includes html,
                      "Cannot draw the chart: This report has no collected metrics data"
      assert_not_includes html, "<canvas"
    end

    should "use an alphanumeric random marker that never leaks into the output" do
      marker = send(:chart_marker)

      assert_match(/\A[a-z0-9]+\z/, marker)
      assert_not_equal marker, send(:chart_marker)

      first = render_health_report_markdown(DIRECTIVE_BODY, report: @report)
      second = render_health_report_markdown(DIRECTIVE_BODY, report: @report)

      assert_equal first, second
      assert_not_includes first, "aihelperchart"
    end

    should "raise when the rendered body lost a marker paragraph" do
      stubs(:md_to_html).returns("<p>unrelated</p>")

      error = assert_raises(RuntimeError) do
        render_health_report_markdown(DIRECTIVE_BODY, report: @report)
      end

      assert_match(/marker/i, error.message)
    end
  end

  context "ai_helper_chart_heads" do
    setup do
      @original_importmap = Rails.application.importmap
    end

    teardown do
      Rails.instance_variable_set(:@_importmap, @original_importmap)
    end

    should "emit chart.min exactly once when the importmap has no chart.js pin" do
      importmap = Object.new
      def importmap.instance_variable_get(_name)
        { "other.lib" => Object.new }
      end
      Rails.application.stubs(importmap: importmap)

      ai_helper_chart_heads
      heads = content_for(:header_tags)

      assert_includes heads, "chart.min"

      ai_helper_chart_heads

      assert_equal 1, content_for(:header_tags).scan("chart.min").size
    end

    should "emit nothing when the importmap pins chart.js" do
      importmap = Object.new
      def importmap.instance_variable_get(_name)
        { "chart.js" => Object.new }
      end
      Rails.application.stubs(importmap: importmap)

      ai_helper_chart_heads

      assert_nil content_for(:header_tags)
    end
  end

  context "ai_helper_markdown_toolbar_heads" do
    setup do
      @original_text_formatting = Setting.text_formatting
      Setting.text_formatting = "textile"
    end

    teardown do
      Setting.text_formatting = @original_text_formatting
    end

    should "emit the CommonMark toolbar assets regardless of the text formatting setting" do
      ai_helper_markdown_toolbar_heads
      heads = content_for(:header_tags)

      assert_includes heads, "jstoolbar/jstoolbar"
      assert_includes heads, "jstoolbar/common_mark"
      assert_includes heads, %(jstoolbar/lang/jstoolbar-#{current_language.to_s.downcase})
      assert_includes heads, "jstoolbar.css"
      assert_includes heads, "wikiImageMimeTypes"
      assert_includes heads, "userHlLanguages"
      assert_not_includes heads, "jstoolbar/textile"
    end

    should "emit the assets only once when called twice" do
      ai_helper_markdown_toolbar_heads
      ai_helper_markdown_toolbar_heads
      heads = content_for(:header_tags)

      assert_equal 1, heads.scan("jstoolbar/common_mark").size
      assert_equal 1, heads.scan("jstoolbar.css").size
    end
  end

  context "health_report_edit_notice_text" do
    setup do
      @report = AiHelperHealthReport.create!(project: Project.find(1), user: User.find(1), health_report: "Body")
    end

    should "return nil for an unedited report" do
      assert_nil health_report_edit_notice_text(@report)
    end

    should "return a plain-text quote line for an edited report" do
      editor = User.find(2)
      @report.update_content("Edited body", editor)

      text = health_report_edit_notice_text(@report)

      assert text.start_with?("> #{l("ai_helper.health_report_edit.edited")}: ")
      assert_includes text, editor.name
      assert_includes text, format_time(@report.last_edited_on)
      assert_no_match(/[<>]/, text.sub(/\A> /, ""))
      assert_not_includes text, "\n"
    end
  end

  # Extract the JSON payload of the first chart canvas from rendered HTML.
  # The data attribute value is ERB-escaped, so it is unescaped before parsing.
  def extract_chart_json(html)
    match = html.match(/data-ai-helper-chart="([^"]*)"/)
    raise "data-ai-helper-chart attribute not found in output" unless match

    JSON.parse(CGI.unescapeHTML(match[1]))
  end
end
