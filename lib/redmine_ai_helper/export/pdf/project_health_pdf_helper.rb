# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/scanner"
require "redmine_ai_helper/health_report_chart/resolver"
require "redmine_ai_helper/export/pdf/project_health_pdf_chart_helper"

module RedmineAiHelper
  # Export functionality
  module Export
    # PDF export functionality
    module PDF
      # Helper module for generating project health report PDFs
      module ProjectHealthPdfHelper
        include Redmine::I18n
        include ApplicationHelper
        include AiHelperHelper
        include RedmineAiHelper::Export::PDF::ProjectHealthPdfChartHelper

        # Generate PDF for project health report
        # @param project [Project] The project object
        # @param health_report [String] The health report content
        # @param options [Hash] Optional settings. :edit_notice is a line shown below
        #   the header when the report was edited by a user. :charts is the
        #   HealthReportChart::Resolver that draws chart directives; without it,
        #   directives resolve against no metrics (Resolver.new(nil)).
        # @return [String] PDF content as binary string
        # @raise [ArgumentError] when :charts is not a Resolver, or the body is
        #   neither a String nor nil
        #
        # In an RTL language the whole page is switched to right-to-left with
        # pdf.set_rtl, which also right-aligns the body HTML drawn by
        # RDMwriteFormattedCell. text_align is passed only to the header cells,
        # the edit notice and the chart renderer's own text.
        def project_health_to_pdf(project, health_report, options = {})
          pdf = Redmine::Export::PDF::ITCPDF.new(current_language)
          is_rtl = l(:direction) == "rtl"
          pdf.set_rtl(true) if is_rtl && pdf.respond_to?(:set_rtl)
          pdf.set_title("#{project.name} - #{l('ai_helper.project_health.pdf_title')}")
          pdf.alias_nb_pages
          pdf.footer_date = format_date(User.current.today)

          bottom_margin = pdf.get_footer_margin
          left_margin = pdf.get_original_margins["left"] || 10
          pdf.set_auto_page_break(true, bottom_margin)
          pdf.add_page

          text_align = is_rtl ? "R" : "L"
          render_pdf_header_section(pdf, project, left_margin, text_align)
          render_pdf_edit_notice(pdf, options[:edit_notice], left_margin, text_align)

          pdf.SetFontStyle("", 10)
          pdf.set_x(left_margin)
          pdf.set_auto_page_break(true, bottom_margin)
          charts = options.fetch(:charts) { RedmineAiHelper::HealthReportChart::Resolver.new(nil) }
          raise ArgumentError, "charts must be a HealthReportChart::Resolver" unless charts.is_a?(RedmineAiHelper::HealthReportChart::Resolver)
          render_pdf_body(pdf, health_report, charts, left_margin, text_align)

          pdf.output
        end

        private

        def render_pdf_edit_notice(pdf, notice, left_margin, text_align)
          return if notice.blank?

          pdf.set_x(left_margin)
          pdf.SetFontStyle("I", 10)
          pdf.multi_cell(0, 5, notice.sub(/\A>\s*/, ""), 0, text_align)
          pdf.ln(4)
        end

        def render_pdf_header_section(pdf, project, left_margin, text_align)
          pdf.set_x(left_margin)
          render_pdf_header_titles(pdf, project, text_align)
          render_pdf_project_info(pdf, project, text_align)
          render_pdf_project_description(pdf, project, text_align) if project.description.present?
          render_pdf_created_on(pdf, text_align)
          render_pdf_section_separator(pdf, text_align)
        end

        def render_pdf_header_titles(pdf, project, text_align)
          pdf.SetFontStyle("B", 16)
          pdf.cell(0, 10, project.name.to_s, 0, 0, text_align)
          pdf.ln(8)
          pdf.SetFontStyle("B", 14)
          pdf.cell(0, 8, l("ai_helper.project_health.pdf_title"), 0, 0, text_align)
          pdf.ln(10)
        end

        def render_pdf_project_info(pdf, project, text_align)
          pdf.SetFontStyle("B", 12)
          pdf.cell(0, 6, l(:field_project), 0, 0, text_align)
          pdf.ln(6)
          pdf.SetFontStyle("", 10)
          pdf.multi_cell(0, 5, "#{project.name} (#{project.identifier})", 0, text_align)
          pdf.ln(2)
        end

        def render_pdf_project_description(pdf, project, text_align)
          pdf.SetFontStyle("B", 10)
          pdf.cell(0, 5, l(:field_description), 0, 0, text_align)
          pdf.ln(5)
          pdf.SetFontStyle("", 10)
          pdf.multi_cell(0, 5, project.description, 0, text_align)
          pdf.ln(2)
        end

        def render_pdf_created_on(pdf, text_align)
          pdf.SetFontStyle("B", 10)
          pdf.cell(0, 5, l(:field_created_on), 0, 0, text_align)
          pdf.ln(5)
          pdf.SetFontStyle("", 10)
          pdf.cell(0, 5, Time.current.strftime("%Y-%m-%d %H:%M:%S"), 0, 0, text_align)
          pdf.ln(5)
        end

        def render_pdf_section_separator(pdf, text_align)
          pdf.line(pdf.get_x, pdf.get_y, pdf.get_x + 180, pdf.get_y)
          pdf.ln(8)
          pdf.SetFontStyle("B", 12)
          pdf.cell(0, 6, l(:label_ai_helper_project_health_report_content, default: "Health Report Content"), 0, 0, text_align)
          pdf.ln(8)
        end
      end
    end
  end
end
