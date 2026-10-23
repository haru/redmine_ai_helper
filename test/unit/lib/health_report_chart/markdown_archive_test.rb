# frozen_string_literal: true

require_relative "../../../test_helper"
require "zip"
require "redmine_ai_helper/health_report_chart/resolver"
require "redmine_ai_helper/health_report_chart/scanner"
require "redmine_ai_helper/health_report_chart/markdown_archive"

class HealthReportChartMarkdownArchiveTest < ActiveSupport::TestCase
  MarkdownArchive = RedmineAiHelper::HealthReportChart::MarkdownArchive
  Resolver = RedmineAiHelper::HealthReportChart::Resolver

  METRICS = [
    {
      version_id: 12, version_name: "1.0.0",
      metrics: {
        issue_statistics: {
          by_status: { "New" => 3, "Closed" => 5 }, by_assigned_to: { "Alice" => 6 },
          open_issues: 10, closed_issues: 5
        }
      }
    }
  ].to_json

  def entries(zip_binary)
    result = {}
    Zip::InputStream.open(StringIO.new(zip_binary)) do |io|
      while (entry = io.get_next_entry)
        result[entry.name] = io.read.force_encoding("UTF-8")
      end
    end
    result
  end

  def build_archive(markdown, metrics = METRICS)
    entries(MarkdownArchive.build(markdown, resolver: Resolver.new(metrics), base_name: "proj-health-report-20261017"))
  end

  context "MarkdownArchive.build" do
    should "return a zip with the markdown and numbered svg charts in order of appearance" do
      result = build_archive("A\n\n{{ai_helper_chart(status, version=12)}}\n\nB\n\n{{ai_helper_chart(assignee, version=12)}}\n\nC")

      assert_equal [ "proj-health-report-20261017.md", "charts/chart-1.svg", "charts/chart-2.svg" ].sort, result.keys.sort
      assert_includes result["charts/chart-1.svg"], "Issues by Status - 1.0.0"
      assert_includes result["charts/chart-2.svg"], "Issues by Assignee - 1.0.0"
    end

    should "replace each directive line with an image reference surrounded by blank lines" do
      md = build_archive("A\n{{ai_helper_chart(status, version=12)}}\nB")["proj-health-report-20261017.md"]

      assert_equal "A\n\n![Issues by Status - 1.0.0](charts/chart-1.svg)\n\nB", md
    end

    should "escape brackets and backslashes in the image title" do
      metrics = [ { version_id: 12, version_name: "v[1]\\x", metrics: { issue_statistics: { by_status: { "New" => 1 } } } } ].to_json

      md = build_archive("{{ai_helper_chart(status, version=12)}}", metrics)["proj-health-report-20261017.md"]

      assert_includes md, "![Issues by Status - v\\[1\\]\\\\x](charts/chart-1.svg)"
    end

    should "write a no-data svg with the title and message" do
      metrics = [ { version_id: 12, version_name: "1.0.0", metrics: { issue_statistics: { by_status: {} } } } ].to_json

      result = build_archive("{{ai_helper_chart(status, version=12)}}", metrics)

      assert_includes result["proj-health-report-20261017.md"], "![Issues by Status - 1.0.0](charts/chart-1.svg)"
      assert_includes result["charts/chart-1.svg"], "Issues by Status - 1.0.0"
      assert_includes result["charts/chart-1.svg"], I18n.t(:label_no_data)
    end

    should "replace an unavailable directive with a one-line blockquote and no svg" do
      result = build_archive("A\n\n{{ai_helper_chart(burndown, version=12)}}\n\nB")

      message = I18n.t("ai_helper.health_report_chart.unavailable") +
                I18n.t("ai_helper.health_report_chart.errors.unknown_type", type: "burndown")
      assert_equal "A\n\n> #{message}\n\nB", result["proj-health-report-20261017.md"]
      assert_equal [ "proj-health-report-20261017.md" ], result.keys
    end

    should "keep a body without directives byte-identical" do
      body = "# Title\n\nText with `{{ai_helper_chart(status, version=12)}}` inline.\n"

      result = build_archive(body)

      assert_equal body, result["proj-health-report-20261017.md"]
      assert_equal [ "proj-health-report-20261017.md" ], result.keys
    end

    should "leave directives inside fenced code blocks untouched" do
      body = "```\n{{ai_helper_chart(status, version=12)}}\n```\n"

      assert_equal body, build_archive(body)["proj-health-report-20261017.md"]
    end

    should "number only the drawable charts, in order of appearance" do
      result = build_archive("{{ai_helper_chart(burndown, version=12)}}\n\n{{ai_helper_chart(status, version=12)}}")

      assert_equal [ "charts/chart-1.svg", "proj-health-report-20261017.md" ], result.keys.sort
      assert_includes result["proj-health-report-20261017.md"], "![Issues by Status - 1.0.0](charts/chart-1.svg)"
      assert_includes result["charts/chart-1.svg"], "Issues by Status - 1.0.0"
    end

    should "keep the trailing newline of a body that ends with a directive line" do
      md = build_archive("A\n\n{{ai_helper_chart(status, version=12)}}\n")["proj-health-report-20261017.md"]

      assert_equal "A\n\n![Issues by Status - 1.0.0](charts/chart-1.svg)\n", md
    end

    should "replace a directive on the first line" do
      md = build_archive("{{ai_helper_chart(status, version=12)}}\nB")["proj-health-report-20261017.md"]

      assert_equal "![Issues by Status - 1.0.0](charts/chart-1.svg)\n\nB", md
    end

    should "keep the leading blank lines of the body when the body ends with a directive" do
      md = build_archive("\n\nA\n{{ai_helper_chart(status, version=12)}}")["proj-health-report-20261017.md"]

      assert_equal "\n\nA\n\n![Issues by Status - 1.0.0](charts/chart-1.svg)", md
    end

    should "replace two consecutive directive lines" do
      md = build_archive("{{ai_helper_chart(status, version=12)}}\n{{ai_helper_chart(assignee, version=12)}}")["proj-health-report-20261017.md"]

      assert_equal "![Issues by Status - 1.0.0](charts/chart-1.svg)\n\n![Issues by Assignee - 1.0.0](charts/chart-2.svg)", md
    end

    should "write unicode text around a directive as UTF-8" do
      md = build_archive("日本語\n\n{{ai_helper_chart(status, version=12)}}")["proj-health-report-20261017.md"]

      assert_equal "日本語\n\n![Issues by Status - 1.0.0](charts/chart-1.svg)", md
      assert md.valid_encoding?
    end

    should "raise ArgumentError when the resolver is not a Resolver" do
      assert_raises(ArgumentError) { MarkdownArchive.build("text", resolver: "resolver", base_name: "b") }
    end

    should "raise ArgumentError when a directive resolves to neither a Chart nor an Unavailable" do
      Resolver.any_instance.stubs(:resolve).returns(nil)

      assert_raises(ArgumentError) { build_archive("{{ai_helper_chart(status, version=12)}}") }
    end

    should "keep unicode text intact" do
      assert_equal "日本語の本文\n", build_archive("日本語の本文\n")["proj-health-report-20261017.md"]
    end
  end
end
