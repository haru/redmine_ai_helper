# frozen_string_literal: true

require "erb"
require "redmine/i18n"
require "redmine_ai_helper/health_report_chart/chart"

module RedmineAiHelper
  module HealthReportChart
    # Draws a Chart as an SVG document string for the Markdown export. The
    # SVG is assembled from plain strings; no image library and no server
    # fonts are needed (text uses font-family="sans-serif" and is rendered
    # with the viewer's font). The doughnut is drawn from 12 o'clock
    # clockwise with a hole of half the outer radius, matching the screen and
    # PDF renderers (R-004).
    module SvgRenderer
      extend Redmine::I18n

      # The width of the SVG canvas.
      WIDTH = 480
      # The x coordinate of the doughnut center.
      CENTER_X = 100
      # The y coordinate of the doughnut center.
      CENTER_Y = 120
      # The outer radius of the doughnut.
      RADIUS = 80
      # The x coordinate of the doughnut legend.
      LEGEND_X = 210
      # The height of one legend row.
      LEGEND_ROW = 22
      # The width of the longest bar.
      BAR_MAX_WIDTH = 300
      # The height of one bar row (label and bar).
      BAR_ROW = 40
      # The baseline y coordinate of the title.
      TITLE_Y = 24
      # The font attribute shared by all text elements.
      FONT = 'font-family="sans-serif"'

      class << self
        # Render the chart as an SVG string.
        # @param chart [Chart] the chart to draw
        # @return [String] the SVG document
        # @raise [ArgumentError] when chart is not a Chart
        def render(chart)
          raise ArgumentError, "chart must be a Chart" unless chart.is_a?(Chart)

          body, height =
            if chart.no_data?
              no_data_body
            elsif chart.form == :doughnut
              doughnut_body(chart)
            else
              bar_body(chart)
            end
          wrap(chart.title, body, height)
        end

        private

        def wrap(title, body, height)
          %(<svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{height}" viewBox="0 0 #{WIDTH} #{height}">\n) +
            %(<text x="10" y="#{TITLE_Y}" #{FONT} font-size="14" font-weight="bold">#{escape(title)}</text>\n) +
            body + "</svg>\n"
        end

        def no_data_body
          [ %(<text x="10" y="52" #{FONT} font-size="12">#{escape(l(:label_no_data))}</text>\n), 70 ]
        end

        def doughnut_body(chart)
          slices = chart.items.select { |item| item.value > 0 }
          total = chart.items.sum(&:value).to_f
          body = +""
          if slices.length == 1
            body << full_ring(slices.first)
          else
            start_angle = 0.0
            slices.each do |item|
              end_angle = start_angle + (2 * Math::PI * item.value / total)
              body << sector(item, start_angle, end_angle)
              start_angle = end_angle
            end
          end
          body << legend(chart.items)
          [ body, [ CENTER_Y + RADIUS + 20, 40 + (chart.items.length * LEGEND_ROW) ].max ]
        end

        def full_ring(item)
          %(<circle cx="#{CENTER_X}" cy="#{CENTER_Y}" r="#{RADIUS}" #{colors(item)}/>\n) +
            %(<circle cx="#{CENTER_X}" cy="#{CENTER_Y}" r="#{fmt(RADIUS / 2.0)}" fill="white"/>\n)
        end

        def sector(item, start_angle, end_angle)
          inner = RADIUS / 2.0
          large = end_angle - start_angle > Math::PI ? 1 : 0
          x1, y1 = point(RADIUS, start_angle)
          x2, y2 = point(RADIUS, end_angle)
          ix1, iy1 = point(inner, start_angle)
          ix2, iy2 = point(inner, end_angle)
          d = "M #{fmt(x1)} #{fmt(y1)} A #{fmt(RADIUS)} #{fmt(RADIUS)} 0 #{large} 1 #{fmt(x2)} #{fmt(y2)} " \
              "L #{fmt(ix2)} #{fmt(iy2)} A #{fmt(inner)} #{fmt(inner)} 0 #{large} 0 #{fmt(ix1)} #{fmt(iy1)} Z"
          %(<path d="#{d}" #{colors(item)}/>\n)
        end

        # A point at the radius, measured clockwise from 12 o'clock.
        def point(radius, angle)
          [ CENTER_X + (radius * Math.sin(angle)), CENTER_Y - (radius * Math.cos(angle)) ]
        end

        def legend(items)
          items.each_with_index.map do |item, index|
            y = 40 + (index * LEGEND_ROW)
            %(<rect x="#{LEGEND_X}" y="#{y}" width="12" height="12" #{colors(item)}/>\n) +
              %(<text x="#{LEGEND_X + 18}" y="#{y + 11}" #{FONT} font-size="12">#{escape(item.label)}</text>\n)
          end.join
        end

        def bar_body(chart)
          max_value = chart.items.map(&:value).max.to_f
          body = chart.items.each_with_index.map do |item, index|
            y = 48 + (index * BAR_ROW)
            line = %(<text x="10" y="#{y}" #{FONT} font-size="12">#{escape(item.label)}</text>\n)
            if item.value > 0
              width = fmt(BAR_MAX_WIDTH * item.value / max_value)
              line += %(<rect x="10" y="#{y + 6}" width="#{width}" height="14" #{colors(item)}/>\n)
            end
            line
          end.join
          [ body, 48 + (chart.items.length * BAR_ROW) ]
        end

        def colors(item)
          %(fill="#{item.border_color}" fill-opacity="#{Palette::FILL_ALPHA}" stroke="#{item.border_color}")
        end

        # Integers print without a fraction; others with at most 2 decimals.
        def fmt(number)
          rounded = number.to_f.round(2)
          rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s
        end

        def escape(text)
          ERB::Util.html_escape(text)
        end
      end
    end
  end
end
