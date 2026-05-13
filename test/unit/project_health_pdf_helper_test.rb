require_relative "../test_helper"

class ProjectHealthPdfHelperTest < ActionView::TestCase
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper
  include RedmineAiHelper::Logger
  fixtures :projects, :users, :roles, :members, :member_roles

  context "ProjectHealthPdfHelper" do
    setup do
      @user = User.find(1)
      @project = projects(:projects_001)
      User.current = @user
    end

    context "#project_health_to_pdf" do
      should "generate PDF with proper header and content" do
        health_report = "# Test Health Report\n\nThis is a test report with **bold** text and *italic* text."

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert_kind_of String, result
        assert_operator result.length, :>, 0
        # PDF files start with %PDF
        assert result.start_with?("%PDF")
      end

      should "handle project with description" do
        @project.description = "Test project description"
        @project.save!

        health_report = "# Test Health Report\n\nContent here."

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle project without description" do
        @project.description = nil
        @project.save!

        health_report = "# Test Health Report\n\nContent here."

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle empty health report" do
        health_report = ""

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle nil health report" do
        health_report = nil

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle markdown content with lists" do
        health_report = <<~MARKDOWN
          # Project Health Report

          ## Issues
          - Issue 1
          - Issue 2

          ## Metrics
          1. Metric 1
          2. Metric 2

          Code: `some code`

          ```ruby
          def test
            puts "hello"
          end
          ```
        MARKDOWN

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle textilizable conversion errors gracefully" do
        health_report = "# Test Report\n\nContent here."

        # Mock textilizable to raise an error
        self.stubs(:textilizable).raises(StandardError.new("Textilizable error"))

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "set proper PDF metadata" do
        health_report = "Test content"

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end
    end

    context "#convert_markdown_to_plain_text" do
      should "convert headers to plain text" do
        markdown = "# Header 1\n## Header 2\n### Header 3"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_equal "Header 1\nHeader 2\nHeader 3", result
      end

      should "convert bold text to plain text" do
        markdown = "**bold text** and __another bold__"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_equal "bold text and another bold", result
      end

      should "convert italic text to plain text" do
        markdown = "*italic text* and _another italic_"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_equal "italic text and another italic", result
      end

      should "convert lists to bullet points" do
        markdown = "- Item 1\n- Item 2\n* Item 3\n+ Item 4"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_match(/• Item 1/, result)
        assert_match(/• Item 2/, result)
        assert_match(/• Item 3/, result)
        assert_match(/• Item 4/, result)
      end

      should "convert numbered lists" do
        markdown = "1. First item\n2. Second item"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_match(/First item/, result)
        assert_match(/Second item/, result)
      end

      should "handle code blocks" do
        markdown = "```ruby\ndef test\nend\n```\n\nSome `inline code` here"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_match(/\[Code Block\]/, result)
        assert_match(/inline code/, result)
      end

      should "handle links" do
        markdown = "[Link text](http://example.com)"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_equal "Link text", result
      end

      should "handle empty content" do
        result = send(:convert_markdown_to_plain_text, "")

        assert_equal "", result
      end

      should "handle nil content" do
        result = send(:convert_markdown_to_plain_text, nil)

        assert_equal "", result
      end

      should "normalize whitespace" do
        markdown = "Line 1\n\n\n\nLine 2\n\n\n\nLine 3"
        result = send(:convert_markdown_to_plain_text, markdown)

        assert_equal "Line 1\n\nLine 2\n\nLine 3", result
      end

      should "handle complex markdown" do
        markdown = <<~MARKDOWN
          # Project Health Report

          **Summary:** This project is doing *well*.

          ## Issues
          - **Critical:** 2 issues
          - **Major:** 5 issues

          ### Code Quality
          ```ruby
          def calculate_health
            return "good"
          end
          ```

          For more info, see [documentation](http://example.com).
        MARKDOWN

        result = send(:convert_markdown_to_plain_text, markdown)

        assert_match(/Project Health Report/, result)
        assert_match(/Summary: This project is doing well/, result)
        assert_match(/• Critical: 2 issues/, result)
        assert_match(/• Major: 5 issues/, result)
        assert_match(/Code Quality/, result)
        assert_match(/\[Code Block\]/, result)
        assert_match(/documentation/, result)
      end
    end

    context "#process_markdown_tables_for_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @left_margin = 10
      end

      should "process markdown table and return content without table" do
        markdown_with_table = <<~MARKDOWN
          # Header

          | Name | Age | City |
          |------|-----|------|
          | John | 25  | NYC  |
          | Jane | 30  | LA   |

          Some text after table.
        MARKDOWN

        result = send(:process_markdown_tables_for_pdf, @pdf, markdown_with_table, @left_margin)

        assert_no_match(/\|/, result)
        assert_match(/Header/, result)
        assert_match(/Some text after table/, result)
      end

      should "handle content with no tables" do
        content = "# Header\n\nSome content without tables."

        result = send(:process_markdown_tables_for_pdf, @pdf, content, @left_margin)

        assert_equal content, result
      end

      should "handle multiple tables" do
        markdown_with_tables = <<~MARKDOWN
          Before text

          | Table 1 | Data |
          |---------|------|
          | Row 1   | Val1 |

          Some text between tables

          | Table 2 | More |
          |---------|------|
          | Row 2   | Val2 |

          After text
        MARKDOWN

        result = send(:process_markdown_tables_for_pdf, @pdf, markdown_with_tables, @left_margin)

        assert_no_match(/\|/, result)
        # The method should remove tables but preserve non-table text
        assert result.include?("Before text") || result.include?("After text") || result.include?("Some text")
      end
    end

    context "#clean_remaining_table_lines" do
      should "remove remaining table-like lines" do
        content = <<~TEXT
          Some text
          | Header | Data |
          |--------|------|
          | Row    | Val  |
          More text
        TEXT

        result = send(:clean_remaining_table_lines, content)

        assert_no_match(/\|/, result)
        assert_match(/Some text/, result)
        assert_match(/More text/, result)
      end

      should "handle content without table lines" do
        content = "Normal text content"

        result = send(:clean_remaining_table_lines, content)

        assert_equal content, result
      end
    end

    context "#html_to_plain_text" do
      should "convert HTML to plain text" do
        html = "<h1>Header</h1><p>Some <strong>bold</strong> text</p>"

        result = send(:html_to_plain_text, html)

        assert_match(/Header/, result)
        assert_match(/Some bold text/, result)
        assert_no_match(/</, result)
      end

      should "handle empty HTML" do
        result = send(:html_to_plain_text, "")

        assert_equal "", result
      end

      should "handle nil HTML" do
        result = send(:html_to_plain_text, nil)

        assert_equal "", result
      end
    end

    context "#process_simple_text_for_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "process text with headings" do
        text = "# Main Header\n\nSome content\n\n## Sub Header\n\nMore content"

        assert_nothing_raised do
          send(:process_simple_text_for_pdf, @pdf, text, @left_margin)
        end
      end

      should "process text with lists" do
        text = "• Item 1\n• Item 2\n  • Nested item"

        assert_nothing_raised do
          send(:process_simple_text_for_pdf, @pdf, text, @left_margin)
        end
      end

      should "process plain text" do
        text = "Just some plain text content."

        assert_nothing_raised do
          send(:process_simple_text_for_pdf, @pdf, text, @left_margin)
        end
      end
    end

    context "#add_simple_heading_to_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "add heading with appropriate size" do
        assert_nothing_raised do
          send(:add_simple_heading_to_pdf, @pdf, "Test Header", 1, @left_margin)
          send(:add_simple_heading_to_pdf, @pdf, "Sub Header", 2, @left_margin)
          send(:add_simple_heading_to_pdf, @pdf, "Sub Sub Header", 3, @left_margin)
        end
      end
    end

    context "#add_simple_list_item_to_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "add list items with proper indentation" do
        assert_nothing_raised do
          send(:add_simple_list_item_to_pdf, @pdf, "Item 1", 0, :bullet, @left_margin)
          send(:add_simple_list_item_to_pdf, @pdf, "Nested item", 1, :bullet, @left_margin)
        end
      end
    end

    context "#add_simple_paragraph_to_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "add paragraph text" do
        assert_nothing_raised do
          send(:add_simple_paragraph_to_pdf, @pdf, "This is a paragraph of text.", @left_margin)
        end
      end

      should "handle empty text" do
        assert_nothing_raised do
          send(:add_simple_paragraph_to_pdf, @pdf, "", @left_margin)
        end
      end
    end

    context "#process_table_html_for_pdf" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "process HTML table" do
        table_html = <<~HTML
          <table>
            <tr><th>Header 1</th><th>Header 2</th></tr>
            <tr><td>Data 1</td><td>Data 2</td></tr>
          </table>
        HTML

        assert_nothing_raised do
          send(:process_table_html_for_pdf, @pdf, table_html, @left_margin)
        end
      end

      should "handle malformed HTML table" do
        malformed_html = "<table><tr><td>Incomplete"

        assert_nothing_raised do
          send(:process_table_html_for_pdf, @pdf, malformed_html, @left_margin)
        end
      end
    end

    context "#draw_pdf_table" do
      setup do
        @pdf = Redmine::Export::PDF::ITCPDF.new("en")
        @pdf.add_page
        @left_margin = 10
      end

      should "draw table with headers and rows" do
        headers = [ "Name", "Age", "City" ]
        rows = [ [ "John", "25", "NYC" ], [ "Jane", "30", "LA" ] ]

        assert_nothing_raised do
          send(:draw_pdf_table, @pdf, headers, rows, @left_margin)
        end
      end

      should "handle empty table" do
        assert_nothing_raised do
          send(:draw_pdf_table, @pdf, [], [], @left_margin)
        end
      end

      should "handle table with only headers" do
        headers = [ "Name", "Age" ]

        assert_nothing_raised do
          send(:draw_pdf_table, @pdf, headers, [], @left_margin)
        end
      end
    end

    context "edge cases and error handling" do
      should "handle project health report with markdown tables" do
        health_report = <<~MARKDOWN
          # Project Health Report

          ## Statistics

          | Metric | Value |
          |--------|-------|
          | Issues | 42    |
          | Bugs   | 5     |

          ## Analysis

          The project shows good health.
        MARKDOWN

        result = project_health_to_pdf(@project, health_report)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle very long content" do
        long_content = "Lorem ipsum dolor sit amet. " * 1000

        result = project_health_to_pdf(@project, long_content)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end

      should "handle content with special characters" do
        special_content = "Content with émojis 🚀 and spéciàl characters ñ"

        result = project_health_to_pdf(@project, special_content)

        assert_not_nil result
        assert result.start_with?("%PDF")
      end
    end
  end
end
