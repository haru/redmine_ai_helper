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
        # @param options [Hash] Optional parameters
        # @return [String] PDF content as binary string
        def project_health_to_pdf(project, health_report, options = {})
          pdf = Redmine::Export::PDF::ITCPDF.new(current_language)

          # Check if current language is RTL
          is_rtl = l(:direction) == 'rtl'

          # Set RTL support if needed
          if is_rtl
            # Enable RTL support in PDF
            pdf.set_rtl(true) if pdf.respond_to?(:set_rtl)
          end

          pdf.set_title("#{project.name} - #{l('ai_helper.project_health.pdf_title')}")
          pdf.alias_nb_pages
          pdf.footer_date = format_date(User.current.today)

          # Get margins for proper layout
          bottom_margin = pdf.get_footer_margin
          left_margin = pdf.get_original_margins['left'] || 10
          pdf.set_auto_page_break(true, bottom_margin)
          pdf.add_page

          # Determine text alignment based on language direction
          text_align = is_rtl ? 'R' : 'L'

          # Header
          pdf.set_x(left_margin)
          pdf.SetFontStyle('B', 16)
          pdf.cell(0, 10, "#{project.name}", 0, 0, text_align)
          pdf.ln(8)

          pdf.SetFontStyle('B', 14)
          pdf.cell(0, 8, l('ai_helper.project_health.pdf_title'), 0, 0, text_align)
          pdf.ln(10)

          # Project information section
          pdf.SetFontStyle('B', 12)
          pdf.cell(0, 6, l(:field_project), 0, 0, text_align)
          pdf.ln(6)

          pdf.SetFontStyle('', 10)
          pdf.multi_cell(0, 5, "#{project.name} (#{project.identifier})", 0, text_align)
          pdf.ln(2)

          if project.description.present?
            pdf.SetFontStyle('B', 10)
            pdf.cell(0, 5, l(:field_description), 0, 0, text_align)
            pdf.ln(5)
            pdf.SetFontStyle('', 10)
            pdf.multi_cell(0, 5, project.description, 0, text_align)
            pdf.ln(2)
          end

          # Generation date
          pdf.SetFontStyle('B', 10)
          pdf.cell(0, 5, l(:field_created_on), 0, 0, text_align)
          pdf.ln(5)
          pdf.SetFontStyle('', 10)
          creation_datetime = Time.current.strftime("%Y-%m-%d %H:%M:%S")
          pdf.cell(0, 5, creation_datetime, 0, 0, text_align)
          pdf.ln(5)

          # Add separator line
          pdf.line(pdf.get_x, pdf.get_y, pdf.get_x + 180, pdf.get_y)
          pdf.ln(8)

          # Health report content
          pdf.SetFontStyle('B', 12)
          pdf.cell(0, 6, l(:label_ai_helper_project_health_report_content, default: "Health Report Content"), 0, 0, text_align)
          pdf.ln(8)

          # Use Redmine's existing text formatting for PDF
          pdf.SetFontStyle('', 10)
          # Set left margin for content and ensure auto page break with bottom margin
          pdf.set_x(left_margin)
          pdf.set_auto_page_break(true, bottom_margin)

          # Process the content with table formatting support
          begin
            # First, process any markdown tables in the raw content
            content_without_tables = process_markdown_tables_for_pdf(pdf, health_report, left_margin, is_rtl)

            # Then process remaining content via textilizable if there's non-table content
            if content_without_tables.strip.present?
              # Remove any remaining table-like lines that might not have been caught
              cleaned_content = clean_remaining_table_lines(content_without_tables)

              if cleaned_content.strip.present?
                formatted_content = textilizable(cleaned_content, :object => project, :only_path => false)
                # Convert to plain text and process with simple formatting
                plain_text = html_to_plain_text(formatted_content)
                process_simple_text_for_pdf(pdf, plain_text, left_margin, is_rtl)
              end
            end
          rescue => e
            ai_helper_logger.error "Error processing content for PDF: #{e.message}"
            # Fallback to simple text processing if textilizable fails
            plain_text = convert_markdown_to_plain_text(health_report)
            pdf.multi_cell(0, 5, plain_text, 0, text_align)
          end

          pdf.output
        end

        private

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
              next unless line.start_with?('|') && line.end_with?('|')

              # Remove leading/trailing |
              cells = line[1..-2].split('|').map(&:strip)

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

          return processed_content
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
          text = text.gsub(/[ \t]+/, ' ') # Multiple spaces to single space
          text = text.strip

          return text
        end

        # Process simple text for PDF with basic formatting
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text_content [String] The plain text content to process
        # @param left_margin [Integer] The left margin for content
        # @param is_rtl [Boolean] Whether the language is RTL
        def process_simple_text_for_pdf(pdf, text_content, left_margin, is_rtl = false)
          return if text_content.blank?

          # Determine text alignment based on language direction
          text_align = is_rtl ? 'R' : 'L'

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
        def add_simple_heading_to_pdf(pdf, text, level, left_margin, text_align = 'L')
          font_size = case level
                     when 1 then 14
                     when 2 then 12
                     when 3 then 11
                     else 10
                     end

          pdf.ln(4)
          pdf.set_x(left_margin)
          pdf.SetFontStyle('B', font_size)
          pdf.multi_cell(0, 6, text, 0, text_align)
          pdf.ln(2)
        end

        # Add simple list item to PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text [String] The item text
        # @param indent_level [Integer] The indentation level
        # @param type [Symbol] :ordered or :unordered
        # @param left_margin [Integer] The base left margin
        # @param text_align [String] Text alignment ('L' or 'R')
        def add_simple_list_item_to_pdf(pdf, text, indent_level, type, left_margin, text_align = 'L')
          indent = left_margin + (indent_level * 4)
          bullet = type == :ordered ? "• " : "• "

          pdf.set_x(indent)
          pdf.SetFontStyle('', 10)
          pdf.multi_cell(0, 5, "#{bullet}#{text}", 0, text_align)
        end

        # Add simple paragraph to PDF
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param text [String] The paragraph text
        # @param left_margin [Integer] The left margin
        # @param text_align [String] Text alignment ('L' or 'R')
        def add_simple_paragraph_to_pdf(pdf, text, left_margin, text_align = 'L')
          return if text.strip.empty?

          pdf.set_x(left_margin)
          pdf.SetFontStyle('', 10)
          pdf.multi_cell(0, 5, text, 0, text_align)
          pdf.ln(2)
        end

        # Process HTML table for PDF using regex parsing
        # @param pdf [Redmine::Export::PDF::ITCPDF] The PDF object
        # @param table_html [String] The table HTML content
        # @param left_margin [Integer] The left margin for content
        def process_table_html_for_pdf(pdf, table_html, left_margin)
          ai_helper_logger.debug "Processing table HTML: #{table_html}"

          # Extract table rows using regex
          rows = []
          headers = []

          # Extract header from <thead> if present
          thead_match = table_html.match(/<thead[^>]*>(.*?)<\/thead>/m)
          if thead_match
            ai_helper_logger.debug "Found thead: #{thead_match[1]}"
            header_row = thead_match[1]
            header_cells = header_row.scan(/<th[^>]*>(.*?)<\/th>/m).flatten
            headers = header_cells.map { |cell| html_to_plain_text(cell).strip }
            ai_helper_logger.debug "Extracted headers: #{headers}"
          end

          # Extract rows from <tbody> or all <tr> if no thead
          tbody_match = table_html.match(/<tbody[^>]*>(.*?)<\/tbody>/m)
          row_content = tbody_match ? tbody_match[1] : table_html
          ai_helper_logger.debug "Row content: #{row_content[0..200]}"

          # Find all <tr> elements
          tr_matches = row_content.scan(/<tr[^>]*>(.*?)<\/tr>/m)
          ai_helper_logger.debug "Found #{tr_matches.length} tr elements"

          tr_matches.each do |row_match|
            row_html = row_match[0]
            # Extract <td> cells
            cells = row_html.scan(/<td[^>]*>(.*?)<\/td>/m).flatten
            if cells.any?
              row_data = cells.map { |cell| html_to_plain_text(cell).strip }
              rows << row_data
              ai_helper_logger.debug "Added row: #{row_data}"
            elsif headers.empty?
              # If no headers and this might be a header row with <th>
              th_cells = row_html.scan(/<th[^>]*>(.*?)<\/th>/m).flatten
              if th_cells.any?
                headers = th_cells.map { |cell| html_to_plain_text(cell).strip }
                ai_helper_logger.debug "Headers from th: #{headers}"
              end
            end
          end

          # If no headers found, use first row as headers
          if headers.empty? && rows.any?
            headers = rows.shift
            ai_helper_logger.debug "Using first row as headers: #{headers}"
          end

          ai_helper_logger.debug "Final headers: #{headers}, rows: #{rows.length}"

          # Draw the table if we have data
          if headers.any? || rows.any?
            ai_helper_logger.debug "Drawing table with #{headers.length} headers and #{rows.length} rows"
            draw_pdf_table(pdf, headers, rows, left_margin, false) # Default to LTR for HTML tables unless we add RTL parameter
          else
            ai_helper_logger.debug "No table data to draw"
          end
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
          header_align = 'C' # Keep headers centered for all languages
          cell_align = is_rtl ? 'R' : 'L'

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
          pdf.SetFontStyle('B', 9)
          header_row.each_with_index do |header, i|
            is_last = i == header_row.length - 1
            # Truncate text if too long
            display_text = header.length > 25 ? "#{header[0..22]}..." : header
            pdf.cell(col_width, 6, display_text, 1, is_last ? 1 : 0, header_align)
          end

          # Draw data rows
          pdf.SetFontStyle('', 8)
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
          return '' if content.blank?

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
          plain_text.gsub!(/```[^`]*```/m, '[Code Block]')
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
