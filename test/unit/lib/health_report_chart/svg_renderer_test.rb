# frozen_string_literal: true

require_relative "../../../test_helper"
require "rexml/document"
require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/svg_renderer"

class HealthReportChartSvgRendererTest < ActiveSupport::TestCase
  Chart = RedmineAiHelper::HealthReportChart::Chart
  Item = RedmineAiHelper::HealthReportChart::Item
  SvgRenderer = RedmineAiHelper::HealthReportChart::SvgRenderer

  def item(label, value, index = 0)
    Item.new(label: label, value: value, rgb: RedmineAiHelper::HealthReportChart::Palette.color_at(index))
  end

  def chart(form, items, title: "Title", summary: nil)
    Chart.new(title: title, form: form, items: items, summary: summary)
  end

  def parse(svg)
    REXML::Document.new(svg)
  end

  def elements(svg, name)
    REXML::XPath.match(parse(svg), "//#{name}")
  end

  context "SvgRenderer.render" do
    should "raise ArgumentError for anything but a Chart" do
      assert_raises(ArgumentError) { SvgRenderer.render("chart") }
      assert_raises(ArgumentError) { SvgRenderer.render(nil) }
    end

    should "return a well-formed SVG document with sans-serif text" do
      svg = SvgRenderer.render(chart(:bar, [ item("New (3)", 3) ]))

      document = parse(svg)
      assert_equal "svg", document.root.name
      assert_equal "http://www.w3.org/2000/svg", document.root.attributes["xmlns"]
      assert_includes svg, 'font-family="sans-serif"'
    end

    should "escape the title and labels" do
      svg = SvgRenderer.render(chart(:bar, [ item("<b>&\"x\" (1)", 1) ], title: "A<script> & B"))

      assert_not_includes svg, "<script>"
      assert_not_includes svg, "<b>"
      texts = elements(svg, "text").map { |t| t.text }
      assert_includes texts, "A<script> & B"
      assert_includes texts, "<b>&\"x\" (1)"
    end

    context "stacked" do
      should "draw one segment per non-zero item left to right with widths proportional to the values" do
        svg = SvgRenderer.render(chart(:stacked, [ item("A (1)", 1, 0), item("B (3)", 3, 1), item("C (0)", 0, 2) ]))

        segments = elements(svg, "rect").select { |r| r.attributes["height"].to_f > 12 }
        assert_equal 2, segments.length
        widths = segments.map { |r| r.attributes["width"].to_f }
        assert_in_delta widths[0] * 3, widths[1], 0.01
        assert_in_delta SvgRenderer::BAR_MAX_WIDTH, widths.sum, 0.01
        xs = segments.map { |r| r.attributes["x"].to_f }
        assert_in_delta xs[0] + widths[0], xs[1], 0.01
        assert_equal "0.2", segments.first.attributes["fill-opacity"]
        assert_equal "rgb(255, 99, 132)", segments.first.attributes["stroke"]
      end

      should "list every item, including zero counts, in a legend with swatches" do
        svg = SvgRenderer.render(chart(:stacked, [ item("A (1)", 1, 0), item("C (0)", 0, 1) ]))

        texts = elements(svg, "text").map(&:text)
        assert_includes texts, "A (1)"
        assert_includes texts, "C (0)"
        swatches = elements(svg, "rect").select { |r| r.attributes["height"].to_f <= 12 }
        assert_equal 2, swatches.length
      end

      should "never draw circles or arcs" do
        svg = SvgRenderer.render(chart(:stacked, [ item("A (1)", 1, 0), item("B (1)", 1, 1) ]))

        assert_empty elements(svg, "circle")
        assert_empty elements(svg, "path")
      end
    end

    context "tile" do
      should "write the title and the summary as text without shapes" do
        svg = SvgRenderer.render(chart(:tile, [ item("Open (10)", 10, 0), item("Closed (5)", 5, 1) ], title: "Open vs Closed", summary: "5 of 15 closed (33%)"))

        texts = elements(svg, "text").map(&:text)
        assert_includes texts, "Open vs Closed"
        assert_includes texts, "5 of 15 closed (33%)"
        assert_empty elements(svg, "rect")
        assert_empty elements(svg, "path")
        assert_empty elements(svg, "circle")
      end

      should "escape the summary" do
        svg = SvgRenderer.render(chart(:tile, [ item("Open (1)", 1) ], summary: "<b>1 & 2</b>"))

        assert_not_includes svg, "<b>"
        assert_includes elements(svg, "text").map(&:text), "<b>1 & 2</b>"
      end
    end

    context "bar" do
      should "draw a rect per item below its label with width proportional to the value" do
        svg = SvgRenderer.render(chart(:bar, [ item("Alice (6)", 6, 0), item("Bob (2)", 2, 1) ]))

        rects = elements(svg, "rect")
        assert_equal 2, rects.length
        widths = rects.map { |r| r.attributes["width"].to_f }
        assert_in_delta widths[0] / 3.0, widths[1], 0.01
        assert_equal "0.2", rects.first.attributes["fill-opacity"]
        texts = elements(svg, "text").map(&:text)
        assert_includes texts, "Alice (6)"
        assert_includes texts, "Bob (2)"
      end

      should "not draw a bar for a zero value" do
        svg = SvgRenderer.render(chart(:bar, [ item("Alice (6)", 6, 0), item("Bob (0)", 0, 1) ]))

        assert_equal 1, elements(svg, "rect").length
        assert_includes elements(svg, "text").map(&:text), "Bob (0)"
      end
    end

    should "write the title and no-data message for a chart without data" do
      svg = SvgRenderer.render(chart(:bar, [], title: "Empty"))

      texts = elements(svg, "text").map(&:text)
      assert_includes texts, "Empty"
      assert_includes texts, I18n.t(:label_no_data)
      assert_empty elements(svg, "path")
    end
  end
end
