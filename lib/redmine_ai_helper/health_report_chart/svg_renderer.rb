# frozen_string_literal: true

require "erb"
require "redmine/i18n"
require "redmine_ai_helper/health_report_chart/chart"

module RedmineAiHelper
  module HealthReportChart
    # Draws a Chart as an SVG document string for the Markdown export. The
    # SVG is assembled from plain strings; no image library and no server
    # fonts are needed (text uses font-family="sans-serif" and is rendered
    # with the viewer's font). Forms: horizontal bars, one stacked bar or a
    # number tile, matching the screen and PDF renderers (R-004).
    module SvgRenderer
      extend Redmine::I18n

      # The width of the SVG canvas.
      WIDTH = 480
      # The height of one legend row.
      LEGEND_ROW = 22
      # The width of the longest bar, and of the whole stacked bar.
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

          body, height = chart.no_data? ? no_data_body : form_body(chart)
          wrap(chart.title, body, height)
        end

        private

        # @raise [ArgumentError] for a form this renderer cannot draw
        def form_body(chart)
          case chart.form
          when :bar then bar_body(chart)
          when :stacked then stacked_body(chart)
          when :tile then tile_body(chart)
          else raise ArgumentError, "cannot draw the chart form #{chart.form.inspect}"
          end
        end

        def wrap(title, body, height)
          %(<svg xmlns="http://www.w3.org/2000/svg" width="#{WIDTH}" height="#{height}" viewBox="0 0 #{WIDTH} #{height}">\n) +
            %(<text x="10" y="#{TITLE_Y}" #{FONT} font-size="14" font-weight="bold">#{escape(title)}</text>\n) +
            body + "</svg>\n"
        end

        def no_data_body
          [ %(<text x="10" y="52" #{FONT} font-size="12">#{escape(l(:label_no_data))}</text>\n), 70 ]
        end

        # One stacked bar of ordered segments with the legend below it.
        def stacked_body(chart)
          total = chart.items.sum(&:value).to_f
          x = 10.0
          body = +""
          chart.items.select { |item| item.value > 0 }.each do |item|
            width = BAR_MAX_WIDTH * item.value / total
            body << %(<rect x="#{fmt(x)}" y="40" width="#{fmt(width)}" height="24" #{colors(item)}/>\n)
            x += width
          end
          body << legend(chart.items)
          [ body, 80 + (chart.items.length * LEGEND_ROW) ]
        end

        # A number tile: the summary in large text, no shapes.
        def tile_body(chart)
          [ %(<text x="10" y="70" #{FONT} font-size="28" font-weight="bold">#{escape(chart.summary)}</text>\n), 90 ]
        end

        def legend(items)
          items.each_with_index.map do |item, index|
            y = 76 + (index * LEGEND_ROW)
            %(<rect x="10" y="#{y}" width="12" height="12" #{colors(item)}/>\n) +
              %(<text x="28" y="#{y + 11}" #{FONT} font-size="12">#{escape(item.label)}</text>\n)
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
