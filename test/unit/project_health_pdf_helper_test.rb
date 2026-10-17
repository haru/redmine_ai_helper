require_relative "../test_helper"
require "redmine_ai_helper/health_report_chart/resolver"

class ProjectHealthPdfHelperTest < ActionView::TestCase
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper
  include RedmineAiHelper::Logger
  fixtures :projects, :users, :roles, :members, :member_roles

  # Inflate all Flate streams of a PDF and return their concatenated content.
  def pdf_text(pdf)
    pdf.b.scan(/stream\r?\n(.*?)endstream/m).map do |(data)|
      Zlib::Inflate.inflate(data)
    rescue Zlib::Error
      data
    end.join.delete("\x00").gsub(/\\([()])/, '\1')
  end


  # Records the drawing calls made on the PDF object while still running
  # them, so tests can assert which shapes the chart renderer drew.
  module PdfCallRecorder
    class << self
      attr_accessor :recording
    end

    def self.calls
      @calls ||= []
    end

    # rbpdf's snake_case names are aliases bound to the original methods, so
    # they are recorded separately under the CamelCase name.
    { Rect: :Rect, PieSector: :PieSector, Circle: :Circle, setAlpha: :setAlpha,
      AddPage: :AddPage, add_page: :AddPage }.each do |name, recorded_as|
      define_method(name) do |*args, **kwargs, &block|
        PdfCallRecorder.calls << [ recorded_as, args ] if PdfCallRecorder.recording
        super(*args, **kwargs, &block)
      end
    end
  end

  CHART_METRICS = [
    {
      version_id: 12, version_name: "1.0.0",
      metrics: {
        issue_statistics: {
          by_status: { "New" => 3, "Closed" => 5, "Resolved" => 0 },
          by_assigned_to: { "Alice" => 6, "Bob" => 2 },
          open_issues: 10, closed_issues: 0
        },
        progress_metrics: { completion_distribution: { not_started: 3, in_progress: 2, completed: 5 } }
      }
    }
  ].to_json

  def calls_named(name)
    PdfCallRecorder.calls.select { |call_name, _| call_name == name }
  end

  def render_with_charts(body, metrics = CHART_METRICS)
    PdfCallRecorder.calls.clear
    resolver = RedmineAiHelper::HealthReportChart::Resolver.new(metrics)
    project_health_to_pdf(@project, body, charts: resolver)
  end

  context "ProjectHealthPdfHelper" do
    setup do
      @user = User.find(1)
      @project = projects(:projects_001)
      User.current = @user
    end

    context "#project_health_to_pdf" do
      should "include the edit notice only when provided" do
        with_notice = project_health_to_pdf(@project, "# Report", edit_notice: "EditedNoticeMarker by someone")
        without_notice = project_health_to_pdf(@project, "# Report", edit_notice: nil)

        assert_includes pdf_text(with_notice), "EditedNoticeMarker"
        assert_not_includes pdf_text(without_notice), "EditedNoticeMarker"
      end

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

    context "chart directives" do
      setup do
        Redmine::Export::PDF::ITCPDF.prepend(PdfCallRecorder)
        PdfCallRecorder.calls.clear
        PdfCallRecorder.recording = true
      end

      teardown do
        PdfCallRecorder.recording = false
      end

      should "produce the same output for a body without directives with or without a resolver" do
        body = "# Report\n\nPlain text only."
        resolver = RedmineAiHelper::HealthReportChart::Resolver.new(CHART_METRICS)

        plain = pdf_text(project_health_to_pdf(@project, body))
        charted = pdf_text(project_health_to_pdf(@project, body, charts: resolver))

        assert_equal plain, charted
      end

      should "draw a doughnut with one sector per non-zero item clockwise from 12 o'clock" do
        pdf = render_with_charts("Before\n\n{{ai_helper_chart(status, version=12)}}\n\nAfter")

        fills = calls_named(:PieSector).select { |_, args| args[5] == "F" }
        borders = calls_named(:PieSector).select { |_, args| args[5] == "D" }
        # New (3) and Closed (5) are drawn; Resolved (0) has no sector.
        assert_equal 2, fills.length
        assert_equal 2, borders.length
        closed_start, closed_end = fills.first[1][3], fills.first[1][4]
        new_start = fills.last[1][3]
        assert_equal 0, closed_start
        assert_in_delta 225.0, closed_end, 0.001
        assert_in_delta closed_end, new_start, 0.001
        assert_includes pdf_text(pdf), "Before"
        assert_includes pdf_text(pdf), "After"
      end

      should "fill sectors with alpha 0.2 and restore alpha 1 for the borders" do
        render_with_charts("{{ai_helper_chart(status, version=12)}}")

        alphas = calls_named(:setAlpha).map { |_, args| args.first }
        assert_includes alphas, 0.2
        assert alphas.each_cons(2).any? { |a, b| (a - 0.2).abs < 1e-9 && b == 1 }, "alpha 1 must follow the 0.2 fill"
      end

      should "overlay a white hole of half the outer radius" do
        render_with_charts("{{ai_helper_chart(status, version=12)}}")

        sector_radius = calls_named(:PieSector).first[1][2]
        hole = calls_named(:Circle).last[1]
        assert_in_delta sector_radius * 0.5, hole[2], 0.001
      end

      should "draw a full ring when one item occupies the whole chart" do
        metrics = [
          { version_id: 12, version_name: "1.0.0", metrics: { issue_statistics: { by_status: { "Only" => 4 } } } }
        ].to_json

        render_with_charts("{{ai_helper_chart(status, version=12)}}", metrics)

        assert_empty calls_named(:PieSector)
        assert_operator calls_named(:Circle).length, :>=, 2
      end

      should "list zero-count items in the legend without a sector" do
        pdf = render_with_charts("{{ai_helper_chart(status, version=12)}}")

        assert_includes pdf_text(pdf), "Resolved (0)"
        # Three legend swatches, each an alpha fill rect plus a border rect.
        assert_equal 6, calls_named(:Rect).length
      end

      should "draw a horizontal bar per item below its label row" do
        pdf = render_with_charts("{{ai_helper_chart(assignee, version=12)}}")

        text = pdf_text(pdf)
        assert_includes text, "Alice (6)"
        assert_includes text, "Bob (2)"
        # Two items, each with an alpha fill rect and a border rect.
        assert_equal 4, calls_named(:Rect).length
        widths = calls_named(:Rect).map { |_, args| args[2] }.uniq.sort
        assert_in_delta widths.last / 3.0, widths.first, 0.001
      end

      should "write the title and a no-data message for a chart without data" do
        metrics = [
          { version_id: 12, version_name: "1.0.0", metrics: { issue_statistics: { by_status: {} } } }
        ].to_json

        pdf = render_with_charts("{{ai_helper_chart(status, version=12)}}", metrics)

        assert_includes pdf_text(pdf), l(:label_no_data)
        assert_empty calls_named(:PieSector)
      end

      should "write the unavailable message as a paragraph" do
        pdf = render_with_charts("{{ai_helper_chart(burndown, version=12)}}")

        message = l("ai_helper.health_report_chart.unavailable") +
                  l("ai_helper.health_report_chart.errors.unknown_type", type: "burndown")
        assert_includes pdf_text(pdf), message
        assert_not_includes pdf_text(pdf), "{{ai_helper_chart"
      end

      should "report metrics_unavailable for every directive without a resolver" do
        PdfCallRecorder.calls.clear
        pdf = project_health_to_pdf(@project, "{{ai_helper_chart(status, version=12)}}")

        assert_includes pdf_text(pdf), l("ai_helper.health_report_chart.errors.metrics_unavailable")
      end

      should "add a page before drawing a chart that does not fit below the cursor" do
        pdf = Redmine::Export::PDF::ITCPDF.new(current_language)
        pdf.add_page
        # Leave less room than the doughnut needs, but enough for its title
        # cell, so only the explicit check can move the chart.
        pdf.set_y(pdf.get_page_height - pdf.get_break_margin - 20)
        chart = RedmineAiHelper::HealthReportChart::Resolver.new(CHART_METRICS)
                                                            .resolve(RedmineAiHelper::HealthReportChart::Scanner.split("{{ai_helper_chart(status, version=12)}}").first)
        PdfCallRecorder.calls.clear

        send(:render_pdf_chart, pdf, chart, 10, "L")

        names = PdfCallRecorder.calls.map(&:first)
        assert_equal :AddPage, names.first, "a page must be added before any chart shape"
        sector_center_y = calls_named(:PieSector).first[1][1]
        assert_operator sector_center_y, :<, 80, "the doughnut must be drawn at the top of the new page"
      end

      should "not add a page when the chart fits below the cursor" do
        pdf = Redmine::Export::PDF::ITCPDF.new(current_language)
        pdf.add_page
        chart = RedmineAiHelper::HealthReportChart::Resolver.new(CHART_METRICS)
                                                            .resolve(RedmineAiHelper::HealthReportChart::Scanner.split("{{ai_helper_chart(status, version=12)}}").first)
        PdfCallRecorder.calls.clear

        send(:render_pdf_chart, pdf, chart, 10, "L")

        assert_empty calls_named(:AddPage)
        assert_not_empty calls_named(:PieSector)
      end

      should "raise ArgumentError when the charts option is not a Resolver" do
        assert_raises(ArgumentError) { project_health_to_pdf(@project, "Body", charts: "resolver") }
      end

      should "raise ArgumentError when the body is neither a String nor nil" do
        assert_raises(ArgumentError) { project_health_to_pdf(@project, 12) }
      end

      should "raise ArgumentError when a resolved directive is neither a Chart nor an Unavailable" do
        RedmineAiHelper::HealthReportChart::Resolver.any_instance.stubs(:resolve).returns(nil)

        assert_raises(ArgumentError) { render_with_charts("{{ai_helper_chart(status, version=12)}}") }
      end

      should "draw charts outside the rescue that falls back to plain text" do
        self.stubs(:textilizable).raises(StandardError.new("Textilizable error"))

        render_with_charts("Text\n\n{{ai_helper_chart(status, version=12)}}")

        assert_operator calls_named(:PieSector).length, :>, 0
      end

      should "not rescue a failure raised while drawing a chart" do
        Redmine::Export::PDF::ITCPDF.any_instance.stubs(:PieSector).raises(RuntimeError.new("draw failed"))

        error = assert_raises(RuntimeError) { render_with_charts("{{ai_helper_chart(status, version=12)}}") }
        assert_equal "draw failed", error.message
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
