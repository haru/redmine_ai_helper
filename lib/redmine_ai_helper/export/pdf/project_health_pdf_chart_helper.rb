# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/palette"

module RedmineAiHelper
  module Export
    module PDF
      # Draws a health report PDF body the way the screen shows it: the whole
      # body goes through the shared Markdown conversion once
      # (AiHelperHelper#health_report_html_with_chart_markers), then this
      # module renders the resulting HTML — the text between chart markers
      # with Redmine's own PDF renderer, and the charts themselves as rbpdf
      # shapes and text: horizontal bars, one stacked bar, or a number tile,
      # like the screen and SVG renderers (R-004) — at the markers' positions.
      # Used by ProjectHealthPdfHelper.
      module ProjectHealthPdfChartHelper
        include Redmine::I18n

        private

        # Draw the body as the HTML the screen shows. A nil body draws nothing.
        # The marker list is consumed from the front as the walk meets the
        # marker paragraphs, so consecutive and repeated directives each draw
        # their own chart in body order. Errors are not rescued.
        # @param pdf [Redmine::Export::PDF::ITCPDF] the PDF being written
        # @param health_report [String, nil] the Markdown source of the body
        # @param charts [RedmineAiHelper::HealthReportChart::Resolver] the
        #   resolver the marker directives are drawn with
        # @param left_margin [Numeric] the page's left margin
        # @param text_align [String] "L" or "R"; the chart renderer's text
        #   alignment (the body HTML follows pdf.set_rtl instead)
        # @return [void]
        # @raise [ArgumentError] when health_report is neither a String nor nil
        # @raise [RuntimeError] when a chart directive's marker paragraph did
        #   not survive the Markdown pipeline as a top-level <p> paragraph, or
        #   when the body contains images the PDF cannot draw
        def render_pdf_body(pdf, health_report, charts, left_margin, text_align)
          return if health_report.nil?

          parts =
            case health_report
            when String then RedmineAiHelper::HealthReportChart::Scanner.split(health_report)
            else raise ArgumentError, "health_report must be a String or nil"
            end
          html, markers = health_report_html_with_chart_markers(parts)
          fragment = Nokogiri::HTML::DocumentFragment.parse(html)
          raise_unsupported_pdf_images(fragment)
          pending = []
          fragment.children.each do |node|
            marker, directive = markers.first
            if marker && node.element? && node.name == "p" && node.text == marker
              markers = markers.drop(1)
              write_pdf_html(pdf, pending.join, left_margin)
              pending = []
              render_pdf_chart(pdf, charts.resolve(directive), left_margin, text_align)
            else
              pending << node.to_html
            end
          end
          write_pdf_html(pdf, pending.join, left_margin)
          unless markers.empty?
            missing_marker, missing_directive = markers.first
            raise "Chart marker paragraph was not rendered in the report body " \
                  "(#{markers.size} marker(s) left, directive: #{missing_directive.source}, marker: #{missing_marker})"
          end
        end

        # Fail the export when the body carries images: the PDF writer gets an
        # empty attachment list, Redmine's ITCPDF#get_image_filename returns
        # nil for an <img src> matching no attachment, and rbpdf then rescues
        # its own error and draws nothing (rbpdf#proc_image_file). An <img>
        # would therefore vanish silently, so the export raises instead.
        # @param fragment [Nokogiri::HTML::DocumentFragment] the body HTML
        # @return [void]
        # @raise [RuntimeError] when the fragment contains <img> elements
        def raise_unsupported_pdf_images(fragment)
          images = fragment.css("img")
          return if images.empty?

          raise "the report body contains #{images.size} <img> element(s), but images cannot be drawn in the PDF"
        end

        # Draw HTML with Redmine's formatted cell writer. The width 0 means
        # the full column between the margins, and the empty x and y strings
        # mean "start at the current position". Blank HTML draws nothing, so
        # the chunks before the first chart and between two charts add no
        # empty cell. The attachment list is empty because a health report has
        # no attachments.
        def write_pdf_html(pdf, html, left_margin)
          return if html.strip.empty?

          pdf.set_x(left_margin)
          pdf.RDMwriteFormattedCell(0, 5, "", "", html, [])
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

        # Draw the chart "unavailable" message as a plain paragraph. This is
        # the only text this module draws outside Redmine's PDF renderer.
        # @param pdf [RBPDF] the PDF document to draw into
        # @param text [String] the message text; blank text draws nothing
        # @param left_margin [Numeric] x position where the paragraph starts
        # @param text_align [String] "L" or "R"
        def add_simple_paragraph_to_pdf(pdf, text, left_margin, text_align)
          return if text.strip.empty?

          pdf.set_x(left_margin)
          pdf.SetFontStyle("", 10)
          pdf.multi_cell(0, 5, text, 0, text_align)
          pdf.ln(2)
        end

        def render_pdf_drawable_chart(pdf, chart, left_margin, text_align)
          if chart.no_data?
            draw_pdf_chart_title(pdf, chart.title, left_margin)
            pdf.SetFontStyle("", 10)
            pdf.cell(0, 5, l(:label_no_data), 0, 1, text_align)
            pdf.ln(3)
          else
            draw_pdf_chart_form(pdf, chart, left_margin)
          end
        end

        # Draw a chart that has data in its form.
        # @raise [ArgumentError] for a form this helper cannot draw
        def draw_pdf_chart_form(pdf, chart, left_margin)
          case chart.form
          when :bar then draw_pdf_bar_chart(pdf, chart, left_margin)
          when :stacked then draw_pdf_stacked_bar(pdf, chart, left_margin)
          when :tile then draw_pdf_tile(pdf, chart, left_margin)
          else raise ArgumentError, "cannot draw the chart form #{chart.form.inspect}"
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

        # One stacked horizontal bar: a segment per non-zero item, left to
        # right in item order, widths proportional to the values; a legend of
        # every item (zero counts included) follows below the bar.
        def draw_pdf_stacked_bar(pdf, chart, left_margin)
          legend_height = chart.items.length * 6
          ensure_pdf_chart_space(pdf, 6 + 8 + legend_height + 3)
          draw_pdf_chart_title(pdf, chart.title, left_margin)

          total = chart.items.sum(&:value).to_f
          bar_width = 160.0
          bar_y = pdf.get_y + 1
          x = left_margin
          chart.items.select { |item| item.value > 0 }.each do |item|
            width = bar_width * item.value / total
            draw_with_chart_colors(pdf, item.rgb) { |style| pdf.Rect(x, bar_y, width, 6, style) }
            x += width
          end
          pdf.set_y(bar_y + 9)
          draw_pdf_stacked_legend(pdf, chart, left_margin)
          pdf.SetDrawColor(0, 0, 0)
          pdf.ln(3)
        end

        def draw_pdf_stacked_legend(pdf, chart, left_margin)
          pdf.SetFontStyle("", 9)
          chart.items.each do |item|
            row_y = pdf.get_y
            draw_with_chart_colors(pdf, item.rgb) { |style| pdf.Rect(left_margin, row_y + 1, 3, 3, style) }
            pdf.set_xy(left_margin + 5, row_y)
            pdf.cell(0, 5, item.label, 0, 1, "L")
          end
        end

        # A number tile: the title and the summary as text, no shapes.
        def draw_pdf_tile(pdf, chart, left_margin)
          ensure_pdf_chart_space(pdf, 6 + 10 + 3)
          draw_pdf_chart_title(pdf, chart.title, left_margin)
          pdf.set_x(left_margin)
          pdf.SetFontStyle("B", 14)
          pdf.cell(0, 9, chart.summary, 0, 1, "L")
          pdf.SetFontStyle("", 10)
          pdf.ln(3)
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
