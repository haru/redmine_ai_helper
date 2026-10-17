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

  def chart(form, items, title: "Title")
    Chart.new(title: title, form: form, items: items)
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
      svg = SvgRenderer.render(chart(:doughnut, [ item("New (3)", 3) ]))

      document = parse(svg)
      assert_equal "svg", document.root.name
      assert_equal "http://www.w3.org/2000/svg", document.root.attributes["xmlns"]
      assert_includes svg, 'font-family="sans-serif"'
    end

    should "escape the title and labels" do
      svg = SvgRenderer.render(chart(:doughnut, [ item("<b>&\"x\" (1)", 1) ], title: "A<script> & B"))

      assert_not_includes svg, "<script>"
      assert_not_includes svg, "<b>"
      texts = elements(svg, "text").map { |t| t.text }
      assert_includes texts, "A<script> & B"
      assert_includes texts, "<b>&\"x\" (1)"
    end

    context "doughnut" do
      should "draw a ring sector path per non-zero item with outer and inner arcs" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (6)", 6, 0), item("B (2)", 2, 1), item("C (0)", 0, 2) ]))

        paths = elements(svg, "path")
        assert_equal 2, paths.length
        paths.each { |path| assert_equal 2, path.attributes["d"].scan("A").length }
        assert_equal "0.2", paths.first.attributes["fill-opacity"]
        assert_equal "rgb(255, 99, 132)", paths.first.attributes["stroke"]
        assert_equal "rgb(255, 99, 132)", paths.first.attributes["fill"]
      end

      should "start the first sector at 12 o'clock and go clockwise" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (1)", 1, 0), item("B (1)", 1, 1) ]))

        first = elements(svg, "path").first.attributes["d"]
        # The first point is the outer radius straight above the center.
        center_x, center_y, radius = SvgRenderer::CENTER_X, SvgRenderer::CENTER_Y, SvgRenderer::RADIUS
        assert_match(/\AM #{center_x} #{center_y - radius}/, first)
      end

      should "go clockwise and set the large-arc flag for sectors over 180 degrees" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (1)", 1, 0), item("B (3)", 3, 1) ]))

        first, second = elements(svg, "path").map { |path| path.attributes["d"] }
        cx, cy, r = SvgRenderer::CENTER_X, SvgRenderer::CENTER_Y, SvgRenderer::RADIUS
        # A quarter clockwise from 12 o'clock ends at 3 o'clock (right of the center).
        assert_match(/\AM #{cx} #{cy - r} A #{r} #{r} 0 0 1 #{cx + r} #{cy} /, first)
        assert_match(/\AM #{cx + r} #{cy} A #{r} #{r} 0 1 1 /, second)
      end

      should "make the hole half the outer radius" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (6)", 6, 0), item("B (2)", 2, 1) ]))

        d = elements(svg, "path").first.attributes["d"]
        assert_includes d, "A #{SvgRenderer::RADIUS / 2} #{SvgRenderer::RADIUS / 2}"
      end

      should "draw two circles when one item occupies the whole chart" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (4)", 4, 0), item("B (0)", 0, 1) ]))

        assert_empty elements(svg, "path")
        circles = elements(svg, "circle")
        assert_equal 2, circles.length
        assert_equal "0.2", circles.first.attributes["fill-opacity"]
        assert_equal "white", circles.last.attributes["fill"]
        assert_equal SvgRenderer::RADIUS / 2.0, circles.last.attributes["r"].to_f
      end

      should "draw a legend swatch and label for every item including zero counts" do
        svg = SvgRenderer.render(chart(:doughnut, [ item("A (6)", 6, 0), item("C (0)", 0, 1) ]))

        assert_equal 2, elements(svg, "rect").length
        texts = elements(svg, "text").map(&:text)
        assert_includes texts, "A (6)"
        assert_includes texts, "C (0)"
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
      svg = SvgRenderer.render(chart(:doughnut, [], title: "Empty"))

      texts = elements(svg, "text").map(&:text)
      assert_includes texts, "Empty"
      assert_includes texts, I18n.t(:label_no_data)
      assert_empty elements(svg, "path")
    end
  end
end
