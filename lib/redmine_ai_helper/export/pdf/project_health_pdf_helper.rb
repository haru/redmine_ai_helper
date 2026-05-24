# frozen_string_literal: true


module RedmineAiHelper
  # Export functionality
  module Export
    # PDF export functionality
    module PDF
      # Helper module for generating project health report PDFs
      module ProjectHealthPdfHelper
        include Redmine::I18n
        include ApplicationHelper
        include ActionView::Helpers::SanitizeHelper
        include ActionView::Helpers::TextHelper
        include RedmineAiHelper::Logger

        # Generate PDF for project health report
        # @param project [Project] The project object
        # @param health_report [String] The health report content
        # @param _options [Hash] Reserved for future use; currently ignored.
        # @return [String] PDF content as binary string
        def project_health_to_pdf(project, health_report, _options = {})
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

          pdf.SetFontStyle("", 10)
          pdf.set_x(left_margin)
          pdf.set_auto_page_break(true, bottom_margin)
          render_pdf_report_content(pdf, project, health_report, left_margin, is_rtl, text_align)

          pdf.output
        end

        private

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

        def render_pdf_report_content(pdf, project, health_report, left_margin, is_rtl, text_align)
          begin
            content_without_tables = process_markdown_tables_for_pdf(pdf, health_report, left_margin, is_rtl)
            if content_without_tables.strip.present?
              cleaned_content = clean_remaining_table_lines(content_without_tables)
              if cleaned_content.strip.present?
                formatted_content = textilizable(cleaned_content, object: project, only_path: false)
                process_simple_text_for_pdf(pdf, html_to_plain_text(formatted_content), left_margin, is_rtl)
              end
            end
          rescue => e
            ai_helper_logger.error "Error processing content for PDF: #{e.message}"
            pdf.multi_cell(0, 5, convert_markdown_to_plain_text(health_report), 0, text_align)
          end
        end

        # Process Markdown tables directly for PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param markdown_content [String] The markdown content to process
        # @param left_margin [Integer] The left margin for content
        # @param is_rtl [Boolean] Whether the language is RTL
        # @return [String] Content with tables removed
        def process_markdown_tables_for_pdf(pdf, markdown_content, left_margin, is_rtl = false)
          ai_helper_logger.debug "Processing Markdown content for PDF. Content length: #{markdown_content.length}"
          ai_helper_logger.debug "Full content: #{markdown_content}"

          processed_content = markdown_content.dup
          table_count = 0

          # Find and process markdown tables
          # Pattern matches: | col1 | col2 | ... followed by | --- | --- | ... and data rows
          table_pattern = /(?:^\|.+\|\s*\n)+^\|[\s:|-]+\|\s*\n(?:^\|.+\|\s*\n)*/m

          processed_content.gsub!(table_pattern) do |table_markdown|
            table_count += 1
            ai_helper_logger.debug "Found markdown table #{table_count}: #{table_markdown}"

            lines = table_markdown.strip.split("\n")
            headers = []
            rows = []

            # Parse table lines
            lines.each_with_index do |line, index|
              line = line.strip
              next unless line.start_with?("|") && line.end_with?("|")

              # Remove leading/trailing |
              cells = line[1..-2].split("|").map(&:strip)

              if index == 0
                # First line is headers
                headers = cells
                ai_helper_logger.debug "Headers: #{headers}"
              elsif index == 1
                # Second line is separator, skip
                next
              else
                # Data rows
                rows << cells
                ai_helper_logger.debug "Row: #{cells}"
              end
            end

            # Draw the table
            if headers.any? && rows.any?
              ai_helper_logger.debug "Drawing markdown table with #{headers.length} headers and #{rows.length} rows"
              draw_pdf_table(pdf, headers, rows, left_margin, is_rtl)
            end

            # Return empty string to remove table from text content
            ""
          end

          ai_helper_logger.debug "Total markdown tables found: #{table_count}"
          ai_helper_logger.debug "Content after table removal: #{processed_content}"

          processed_content
        end

        # Clean any remaining table-like lines that weren't caught by the main regex
        # @param content [String] The content to clean
        # @return [String] Content with table lines removed
        def clean_remaining_table_lines(content)
          ai_helper_logger.debug "Cleaning remaining table lines from: #{content}"

          lines = content.split("\n")
          cleaned_lines = []
          removed_lines = []

          lines.each do |line|
            # Skip lines that look like table rows or separators
            if line.strip.match?(/^\|.*\|$/) || line.strip.match?(/^\|[\s:|-]+\|$/)
              removed_lines << line
              next
            end

            cleaned_lines << line
          end

          ai_helper_logger.debug "Removed table lines: #{removed_lines}"
          ai_helper_logger.debug "Final cleaned content: #{cleaned_lines.join("\n")}"

          cleaned_lines.join("\n")
        end

        # Convert HTML to plain text while preserving basic structure
        # @param html [String] The HTML content to convert
        # @return [String] Plain text with preserved structure
        def html_to_plain_text(html)
          return "" if html.blank?

          # First, convert block-level elements to newlines to preserve structure
          # This keeps paragraphs, headings and list items separated in the plain text
          preprocessed_html = html.gsub(/<\/?(h[1-6]|p|div|br|ul|ol|li)\b[^>]*>/i, "\n")

          # Use Rails built-in strip_tags to safely remove all remaining HTML tags
          # This avoids ReDoS vulnerabilities from regex-based HTML stripping
          text = strip_tags(preprocessed_html)

          # Clean up whitespace while preserving structure
          text = text.gsub(/\n\s*\n/, "\n\n") # Multiple newlines to double newline
          text = text.gsub(/[ \t]+/, " ") # Multiple spaces to single space
          text = text.strip

          text
        end

        # Process simple text for PDF with basic formatting
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text_content [String] The plain text content to process
        # @param left_margin [Integer] The left margin for content
        # @param is_rtl [Boolean] Whether the language is RTL
        def process_simple_text_for_pdf(pdf, text_content, left_margin, is_rtl = false)
          return if text_content.blank?

          # Determine text alignment based on language direction
          text_align = is_rtl ? "R" : "L"

          lines = text_content.split("\n")

          lines.each do |line|
            line = line.strip
            next if line.empty?

            # Check if line is a heading (starts with # characters)
            if line.match(/^(#+)\s+(.+)$/)
              level = $1.length
              heading_text = $2
              add_simple_heading_to_pdf(pdf, heading_text, level, left_margin, text_align)

            # Check if line is a list item (starts with - or number.)
            elsif line.match(/^(\s*)([-*•]|\d+\.)\s+(.+)$/)
              indent_level = ($1.length / 2).to_i
              bullet = $2
              item_text = $3
              add_simple_list_item_to_pdf(pdf, item_text, indent_level, bullet.match?(/\d+\./) ? :ordered : :unordered, left_margin, text_align)

            # Regular paragraph text
            else
              add_simple_paragraph_to_pdf(pdf, line, left_margin, text_align)
            end
          end
        end

        # Add simple heading to PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text [String] The heading text
        # @param level [Integer] The heading level (1-6)
        # @param left_margin [Integer] The left margin
        # @param text_align [String] Text alignment ('L' or 'R')
        def add_simple_heading_to_pdf(pdf, text, level, left_margin, text_align = "L")
          font_size = case level
          when 1 then 14
          when 2 then 12
          when 3 then 11
          else 10
          end

          pdf.ln(4)
          pdf.set_x(left_margin)
          pdf.SetFontStyle("B", font_size)
          pdf.multi_cell(0, 6, text, 0, text_align)
          pdf.ln(2)
        end

        # Add simple list item to PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text [String] The item text
        # @param indent_level [Integer] The indentation level
        # @param left_margin [Integer] The base left margin
        # @param text_align [String] Text alignment ('L' or 'R')
        def add_simple_list_item_to_pdf(pdf, text, indent_level, _type, left_margin, text_align = "L")
          indent = left_margin + (indent_level * 4)
          bullet = "• "

          pdf.set_x(indent)
          pdf.SetFontStyle("", 10)
          pdf.multi_cell(0, 5, "#{bullet}#{text}", 0, text_align)
        end

        # Add simple paragraph to PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text [String] The paragraph text
        # @param left_margin [Integer] The left margin
        # @param text_align [String] Text alignment ('L' or 'R')
        def add_simple_paragraph_to_pdf(pdf, text, left_margin, text_align = "L")
          return if text.strip.empty?

          pdf.set_x(left_margin)
          pdf.SetFontStyle("", 10)
          pdf.multi_cell(0, 5, text, 0, text_align)
          pdf.ln(2)
        end

        # Process HTML table for PDF using regex parsing
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param table_html [String] The table HTML content
        # @param left_margin [Integer] The left margin for content
        def process_table_html_for_pdf(pdf, table_html, left_margin)
          ai_helper_logger.debug "Processing table HTML: #{table_html}"
          headers, rows = extract_table_data_from_html(table_html)
          ai_helper_logger.debug "Final headers: #{headers}, rows: #{rows.length}"
          if headers.any? || rows.any?
            draw_pdf_table(pdf, headers, rows, left_margin, false)
          else
            ai_helper_logger.debug "No table data to draw"
          end
        end

        def extract_table_data_from_html(table_html)
          headers = []
          rows = []

          thead_match = table_html.match(/<thead[^>]*>(.*?)<\/thead>/m)
          if thead_match
            header_cells = thead_match[1].scan(/<th[^>]*>(.*?)<\/th>/m).flatten
            headers = header_cells.map { |cell| html_to_plain_text(cell).strip }
            ai_helper_logger.debug "Extracted headers: #{headers}"
          end

          tbody_match = table_html.match(/<tbody[^>]*>(.*?)<\/tbody>/m)
          row_content = tbody_match ? tbody_match[1] : table_html
          tr_matches = row_content.scan(/<tr[^>]*>(.*?)<\/tr>/m)

          tr_matches.each do |row_match|
            row_html = row_match[0]
            cells = row_html.scan(/<td[^>]*>(.*?)<\/td>/m).flatten
            if cells.any?
              rows << cells.map { |cell| html_to_plain_text(cell).strip }
            elsif headers.empty?
              th_cells = row_html.scan(/<th[^>]*>(.*?)<\/th>/m).flatten
              headers = th_cells.map { |cell| html_to_plain_text(cell).strip } if th_cells.any?
            end
          end

          headers = rows.shift if headers.empty? && rows.any?
          [ headers, rows ]
        end

        # Draw table in PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param headers [Array<String>] Table headers
        # @param rows [Array<Array<String>>] Table rows
        # @param left_margin [Integer] The left margin for content
        # @param is_rtl [Boolean] Whether the language is RTL
        def draw_pdf_table(pdf, headers, rows, left_margin, is_rtl = false)
          return if headers.empty? && rows.empty?

          # Determine text alignment based on language direction
          header_align = "C" # Keep headers centered for all languages
          cell_align = is_rtl ? "R" : "L"

          # Use headers if available, otherwise use first row
          header_row = headers.any? ? headers : (rows.any? ? rows.shift : [])
          return if header_row.empty?

          # Calculate column widths
          total_cols = header_row.length
          available_width = 180 # A4 width minus margins
          col_width = available_width / total_cols

          # Add some spacing before table
          pdf.ln(5)
          pdf.set_x(left_margin)

          # Draw header row
          pdf.SetFontStyle("B", 9)
          header_row.each_with_index do |header, i|
            is_last = i == header_row.length - 1
            # Truncate text if too long
            display_text = header.length > 25 ? "#{header[0..22]}..." : header
            pdf.cell(col_width, 6, display_text, 1, is_last ? 1 : 0, header_align)
          end

          # Draw data rows
          pdf.SetFontStyle("", 8)
          rows.each do |row|
            pdf.set_x(left_margin)

            # Ensure row has same number of columns as header
            normalized_row = row[0, header_row.length]
            while normalized_row.length < header_row.length
              normalized_row << ""
            end

            normalized_row.each_with_index do |cell, i|
              is_last = i == normalized_row.length - 1
              # Truncate text if too long
              display_text = cell.length > 30 ? "#{cell[0..27]}..." : cell
              pdf.cell(col_width, 6, display_text, 1, is_last ? 1 : 0, cell_align)
            end
          end

          # Add some spacing after table
          pdf.ln(5)
        end

        # Convert markdown content to plain text for PDF display
        # @param content [String] The markdown content
        # @return [String] Plain text content
        def convert_markdown_to_plain_text(content)
          return "" if content.blank?

          # Remove markdown formatting and clean up content
          plain_text = content.dup

          # Convert markdown headers to simple text
          # Use character class to avoid ReDoS
          plain_text.gsub!(/^(\#{1,6})\s*([^\n]+)$/, '\2')

          # Convert markdown bold to simple text
          plain_text.gsub!(/\*\*([^*]+)\*\*/, '\1')
          plain_text.gsub!(/__([^_]+)__/, '\1')

          # Convert markdown italic to simple text
          plain_text.gsub!(/\*([^*]+)\*/, '\1')
          plain_text.gsub!(/_([^_]+)_/, '\1')

          # Convert markdown lists to simple format
          # Use character class pattern to avoid ReDoS
          plain_text.gsub!(/^[ \t]*[-*+]\s+([^\n]+)$/, '• \1')
          plain_text.gsub!(/^[ \t]*\d+\.\s+([^\n]+)$/, '\1')

          # Clean up code blocks
          plain_text.gsub!(/```[^`]*```/m, "[Code Block]")
          plain_text.gsub!(/`([^`]+)`/, '\1')

          # Clean up links - use non-greedy with character class to avoid ReDoS
          plain_text.gsub!(/\[([^\]]+)\]\([^)]+\)/, '\1')

          # Remove extra whitespace and normalize line breaks
          plain_text.gsub!(/\n{3,}/, "\n\n")
          plain_text.strip
        end
      end
    end
  end
end
