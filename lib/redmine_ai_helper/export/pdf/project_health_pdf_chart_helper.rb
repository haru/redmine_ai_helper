# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/palette"

module RedmineAiHelper
  module Export
    module PDF
      # Splits a health report body at its chart directives and draws the
      # resolved charts into a PDF with rbpdf shapes and text. Used by
      # ProjectHealthPdfHelper; the doughnut starts at 12 o'clock
      # and goes clockwise with a hole of half the outer radius, like the screen
      # and SVG renderers (R-004).
      module ProjectHealthPdfChartHelper
        include Redmine::I18n

        private

        # Draw the body split at chart directives. Text parts go through the
        # existing text pipeline unchanged; directives are drawn outside its
        # rescue so a drawing failure is not hidden by the plain-text fallback.
        def render_pdf_body(pdf, project, health_report, charts, left_margin, is_rtl, text_align)
          parts =
            case health_report
            when String then RedmineAiHelper::HealthReportChart::Scanner.split(health_report)
            when nil then [ nil ]
            else raise ArgumentError, "health_report must be a String or nil"
            end
          parts.each do |part|
            if part.is_a?(RedmineAiHelper::HealthReportChart::Directive)
              render_pdf_chart(pdf, charts.resolve(part), left_margin, text_align)
            else
              render_pdf_report_content(pdf, project, part, left_margin, is_rtl, text_align)
            end
          end
        end

        # @raise [ArgumentError] when resolved is neither a Chart nor an Unavailable
        def render_pdf_chart(pdf, resolved, left_margin, text_align)
          case resolved
          when RedmineAiHelper::HealthReportChart::Unavailable
            add_simple_paragraph_to_pdf(pdf, resolved.message, left_margin, text_align)
          when RedmineAiHelper::HealthReportChart::Chart
            render_pdf_drawable_chart(pdf, resolved, left_margin, text_align)
          else
            raise ArgumentError, "expected a Chart or an Unavailable, got #{resolved.class}"
          end
        end

        def render_pdf_drawable_chart(pdf, chart, left_margin, text_align)
          if chart.no_data?
            draw_pdf_chart_title(pdf, chart.title, left_margin)
            pdf.SetFontStyle("", 10)
            pdf.cell(0, 5, l(:label_no_data), 0, 1, text_align)
            pdf.ln(3)
          elsif chart.form == :doughnut
            draw_pdf_doughnut(pdf, chart, left_margin)
          else
            draw_pdf_bar_chart(pdf, chart, left_margin)
          end
        end

        # Start a new page when the chart (title + figure) would not fit.
        def ensure_pdf_chart_space(pdf, height)
          limit = pdf.get_page_height - pdf.get_break_margin
          pdf.add_page if pdf.get_y + height > limit
        end

        def draw_pdf_chart_title(pdf, title, left_margin)
          pdf.set_x(left_margin)
          pdf.SetFontStyle("B", 10)
          pdf.cell(0, 6, title, 0, 1, "L")
        end

        # Draw one shape twice in the item's color: first filled with the
        # shared fill alpha (style "F"), then its border opaque (style "D").
        # The block receives the style and draws the shape.
        def draw_with_chart_colors(pdf, rgb)
          pdf.SetFillColor(*rgb)
          pdf.SetDrawColor(*rgb)
          pdf.setAlpha(RedmineAiHelper::HealthReportChart::Palette::FILL_ALPHA)
          yield "F"
          pdf.setAlpha(1)
          yield "D"
        end

        def draw_pdf_doughnut(pdf, chart, left_margin)
          radius = 22.0
          legend_height = chart.items.length * 6
          figure_height = [ (radius * 2) + 4, legend_height ].max
          ensure_pdf_chart_space(pdf, 6 + figure_height + 4)
          draw_pdf_chart_title(pdf, chart.title, left_margin)

          center_x = left_margin + radius + 2
          center_y = pdf.get_y + radius + 2
          draw_pdf_doughnut_slices(pdf, chart, center_x, center_y, radius)
          draw_pdf_doughnut_legend(pdf, chart, left_margin + (radius * 2) + 10, pdf.get_y + 2)
          pdf.set_y(pdf.get_y + figure_height + 4)
        end

        def draw_pdf_doughnut_slices(pdf, chart, center_x, center_y, radius)
          total = chart.items.sum(&:value).to_f
          slices = chart.items.select { |item| item.value > 0 }
          start_angle = 0.0
          slices.each do |item|
            end_angle = start_angle + (360.0 * item.value / total)
            draw_with_chart_colors(pdf, item.rgb) do |style|
              draw_pdf_slice(pdf, slices.length == 1, center_x, center_y, radius, start_angle, end_angle, style)
            end
            start_angle = end_angle
          end
          pdf.SetFillColor(255, 255, 255)
          pdf.Circle(center_x, center_y, radius * 0.5, 0, 360, "F")
        end

        def draw_pdf_slice(pdf, full_ring, center_x, center_y, radius, start_angle, end_angle, style)
          if full_ring
            pdf.Circle(center_x, center_y, radius, 0, 360, style)
          else
            pdf.PieSector(center_x, center_y, radius, start_angle, end_angle, style)
          end
        end

        def draw_pdf_doughnut_legend(pdf, chart, x, y)
          pdf.SetFontStyle("", 9)
          chart.items.each_with_index do |item, index|
            row_y = y + (index * 6)
            draw_with_chart_colors(pdf, item.rgb) { |style| pdf.Rect(x, row_y + 1, 3, 3, style) }
            pdf.set_xy(x + 5, row_y)
            pdf.cell(0, 5, item.label, 0, 0, "L")
          end
          pdf.SetDrawColor(0, 0, 0)
        end

        def draw_pdf_bar_chart(pdf, chart, left_margin)
          row_height = 11
          ensure_pdf_chart_space(pdf, 6 + (chart.items.length * row_height) + 3)
          draw_pdf_chart_title(pdf, chart.title, left_margin)

          max_value = chart.items.map(&:value).max.to_f
          max_width = 120.0
          chart.items.each do |item|
            pdf.set_x(left_margin)
            pdf.SetFontStyle("", 9)
            pdf.cell(0, 5, item.label, 0, 1, "L")
            width = max_width * item.value / max_value
            bar_y = pdf.get_y
            if width > 0
              draw_with_chart_colors(pdf, item.rgb) { |style| pdf.Rect(left_margin, bar_y, width, 4, style) }
            end
            pdf.set_y(bar_y + 6)
          end
          pdf.SetDrawColor(0, 0, 0)
          pdf.ln(3)
        end
      end
    end
  end
end
