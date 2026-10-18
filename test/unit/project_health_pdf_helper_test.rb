require_relative "../test_helper"
require "redmine_ai_helper/health_report_chart/resolver"

class ProjectHealthPdfHelperTest < ActionView::TestCase
  include RedmineAiHelper::Export::PDF::ProjectHealthPdfHelper
  include AiHelperHelper
  include AiHelperDashboardHelper
  include RedmineAiHelper::Logger
  fixtures :projects, :users, :roles, :members, :member_roles

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
      AddPage: :AddPage, add_page: :AddPage,
      RDMwriteFormattedCell: :RDMwriteFormattedCell }.each do |name, recorded_as|
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
          open_issues: 10, closed_issues: 5
        },
        progress_metrics: { completion_distribution: { not_started: 3, in_progress: 2, completed: 5 } }
      }
    }
  ].to_json

  def calls_named(name)
    PdfCallRecorder.calls.select { |call_name, _| call_name == name }
  end

  # The HTML passed to RDMwriteFormattedCell, one string per call, in call order.
  def written_html_chunks
    calls_named(:RDMwriteFormattedCell).map { |_, args| args[4] }
  end

  # Read the tables out of recorded HTML. Raises when the HTML holds no table,
  # so a test never passes by asserting on an empty result.
  # @return [Array<Hash>] one hash per table: :columns, :header, :rows (cell texts)
  def pdf_tables(html)
    tables = Nokogiri::HTML::DocumentFragment.parse(html).css("table")
    raise ArgumentError, "no <table> in the recorded HTML: #{html.inspect}" if tables.empty?

    tables.map do |table|
      rows = table.css("tr").map { |tr| tr.css("th, td").map { |cell| cell.text.strip } }
      { columns: rows.map(&:size).max, header: rows.first, rows: rows.drop(1) }
    end
  end

  ALL_ELEMENTS_BODY = <<~MD
    # Heading One

    ## Heading Two

    ### Heading Three

    A paragraph with **bold**, *italic* and [a link](https://example.com/page).

    - bullet one
      - nested bullet
    - bullet two

    1. first
       1. nested first
    2. second

    | a | b |
    |---|---|
    | 1 | 2 |

    ```
    code line one
    code line two
    ```

    > quoted text

    ---

    {{ai_helper_chart(status, version=12)}}

    Closing paragraph.
  MD

  # The element nodes of an HTML string as [name, text] pairs.
  def element_signature(html)
    Nokogiri::HTML::DocumentFragment.parse(html).children.reject(&:text?).map { |node| [ node.name, node.text ] }
  end

  def assert_pdf_matches_screen
    stubs(:chart_html).returns("")
    report = AiHelperHealthReport.new(metrics: CHART_METRICS)
    screen = render_health_report_markdown(ALL_ELEMENTS_BODY, report: report)

    render_with_charts(ALL_ELEMENTS_BODY)
    pdf_html = written_html_chunks.join

    assert_equal element_signature(screen.to_s), element_signature(pdf_html)
    assert_equal Nokogiri::HTML::DocumentFragment.parse(screen.to_s).css("h1, h2, h3, ul, ol, table, pre, blockquote, hr, a").size,
                 Nokogiri::HTML::DocumentFragment.parse(pdf_html).css("h1, h2, h3, ul, ol, table, pre, blockquote, hr, a").size
    assert_not_includes pdf_html, "\u00B6"
    assert_no_match(/\A#/, pdf_html)
    assert_equal 1, Nokogiri::HTML::DocumentFragment.parse(pdf_html).css("ol ol").size
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

      should "draw status as horizontal bars in count order, with zero counts labelled but not drawn" do
        pdf = render_with_charts("Before\n\n{{ai_helper_chart(status, version=12)}}\n\nAfter")

        text = pdf_text(pdf)
        assert_includes text, "Before"
        assert_includes text, "After"
        assert_operator text.index("Closed (5)"), :<, text.index("New (3)"), "items are ordered by count"
        assert_includes text, "Resolved (0)"
        # Closed and New get an alpha fill rect plus a border rect; Resolved (0) gets none.
        assert_equal 4, calls_named(:Rect).length
        widths = calls_named(:Rect).map { |_, args| args[2] }.uniq.sort
        assert_in_delta widths.last * 3 / 5.0, widths.first, 0.001
        assert_empty calls_named(:PieSector)
        assert_empty calls_named(:Circle)
      end

      should "fill with alpha 0.2 and restore alpha 1 for the borders" do
        render_with_charts("{{ai_helper_chart(status, version=12)}}")

        alphas = calls_named(:setAlpha).map { |_, args| args.first }
        assert_includes alphas, 0.2
        assert alphas.each_cons(2).any? { |a, b| (a - 0.2).abs < 1e-9 && b == 1 }, "alpha 1 must follow the 0.2 fill"
      end

      should "draw progress as one stacked bar with segments in stage order and a legend" do
        pdf = render_with_charts("{{ai_helper_chart(progress, version=12)}}")

        text = pdf_text(pdf)
        %w[Not\ started\ (3) In\ progress\ (2) Completed\ (5)].each { |label| assert_includes text, label }
        assert_operator text.index("Not started (3)"), :<, text.index("In progress (2)")
        assert_operator text.index("In progress (2)"), :<, text.index("Completed (5)")
        fills = calls_named(:Rect).each_slice(1).map(&:first).select { |_, args| args[3] > 3 }
        # Three bar segments (fill + border each) of different heights than the 3 mm swatches.
        assert_equal 6, fills.length
        segment_fills = fills.each_slice(2).map(&:first)
        widths = segment_fills.map { |_, args| args[2] }
        xs = segment_fills.map { |_, args| args[0] }
        assert_in_delta widths[0] * 2 / 3.0, widths[1], 0.01
        assert_in_delta widths[0] * 5 / 3.0, widths[2], 0.01
        assert_in_delta xs[0] + widths[0], xs[1], 0.01
        assert_in_delta xs[1] + widths[1], xs[2], 0.01
        assert_empty calls_named(:PieSector)
      end

      should "list a zero-count stage in the legend without a segment" do
        metrics = [ { version_id: 12, version_name: "1.0.0",
                      metrics: { progress_metrics: { completion_distribution: { not_started: 0, in_progress: 2, completed: 2 } } } } ].to_json

        pdf = render_with_charts("{{ai_helper_chart(progress, version=12)}}", metrics)

        assert_includes pdf_text(pdf), "Not started (0)"
        segments = calls_named(:Rect).select { |_, args| args[3] > 3 }
        assert_equal 4, segments.length
      end

      should "write the open_closed tile as a title and a number, without drawing shapes" do
        pdf = render_with_charts("{{ai_helper_chart(open_closed, version=12)}}")

        text = pdf_text(pdf)
        assert_includes text, "Open vs Closed Issues - 1.0.0"
        assert_includes text, I18n.t("ai_helper.health_report_chart.tile_summary", closed: 5, total: 15, rate: 33)
        assert_empty calls_named(:Rect)
        assert_empty calls_named(:PieSector)
      end

      should "draw a horizontal bar per item below its label row" do
        pdf = render_with_charts("{{ai_helper_chart(assignee, version=12)}}")

        text = pdf_text(pdf)
        assert_includes text, "Alice (6)"
        assert_includes text, "Bob (2)"
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
        assert_empty calls_named(:Rect)
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
        # Leave less room than the chart needs, but enough for its title
        # cell, so only the explicit check can move the chart.
        pdf.set_y(pdf.get_page_height - pdf.get_break_margin - 20)
        chart = RedmineAiHelper::HealthReportChart::Resolver.new(CHART_METRICS)
                                                            .resolve(RedmineAiHelper::HealthReportChart::Scanner.split("{{ai_helper_chart(status, version=12)}}").first)
        PdfCallRecorder.calls.clear

        send(:render_pdf_chart, pdf, chart, 10, "L")

        names = PdfCallRecorder.calls.map(&:first)
        assert_equal :AddPage, names.first, "a page must be added before any chart shape"
        first_bar_y = calls_named(:Rect).first[1][1]
        assert_operator first_bar_y, :<, 80, "the chart must be drawn at the top of the new page"
      end

      should "not add a page when the chart fits below the cursor" do
        pdf = Redmine::Export::PDF::ITCPDF.new(current_language)
        pdf.add_page
        chart = RedmineAiHelper::HealthReportChart::Resolver.new(CHART_METRICS)
                                                            .resolve(RedmineAiHelper::HealthReportChart::Scanner.split("{{ai_helper_chart(status, version=12)}}").first)
        PdfCallRecorder.calls.clear

        send(:render_pdf_chart, pdf, chart, 10, "L")

        assert_empty calls_named(:AddPage)
        assert_not_empty calls_named(:Rect)
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

      should "not rescue a failure raised while drawing a chart" do
        Redmine::Export::PDF::ITCPDF.any_instance.stubs(:Rect).raises(RuntimeError.new("draw failed"))

        error = assert_raises(RuntimeError) { render_with_charts("{{ai_helper_chart(status, version=12)}}") }
        assert_equal "draw failed", error.message
      end

      should "fail the export when the body contains an image the PDF cannot draw" do
        error = assert_raises(RuntimeError) { render_with_charts("Text\n\n![logo](https://example.com/logo.png)") }
        assert_match(/<img>/, error.message)
      end

      should "raise when a marker paragraph is not a top-level paragraph" do
        directive = RedmineAiHelper::HealthReportChart::Directive.new(type: "status", target_kind: :version, target_value: "12", source: "{{ai_helper_chart(status, version=12)}}")
        stubs(:health_report_html_with_chart_markers)
          .returns([ "<blockquote><p>aihelperchartlost</p></blockquote>", [ [ "aihelperchartlost", directive ] ] ])

        error = assert_raises(RuntimeError) { project_health_to_pdf(@project, "text") }
        assert_equal "Chart marker paragraph was not rendered in the report body " \
                     "(1 marker(s) left, directive: {{ai_helper_chart(status, version=12)}}, marker: aihelperchartlost)",
                     error.message
      end
    end

    context "tables drawn from the screen HTML" do
      setup do
        Redmine::Export::PDF::ITCPDF.prepend(PdfCallRecorder)
        PdfCallRecorder.calls.clear
        PdfCallRecorder.recording = true
      end

      teardown do
        PdfCallRecorder.recording = false
      end

      should "raise from the table reader when the HTML has no table" do
        assert_raises(ArgumentError) { pdf_tables("<p>no table here</p>") }
      end

      should "draw two tables separated by a blank line as two tables" do
        body = "| a | b | c | d | e | f | g | h |\n|---|---|---|---|---|---|---|---|\n| 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |\n\n| x | y | z |\n|---|---|---|\n| 9 | 10 | 11 |\n"

        project_health_to_pdf(@project, body)
        tables = pdf_tables(written_html_chunks.join)

        assert_equal([ 8, 3 ], tables.map { |t| t[:columns] })
        assert_equal [ "x", "y", "z" ], tables.last[:header]
        assert_equal [ [ "9", "10", "11" ] ], tables.last[:rows]
        assert_no_match(/---/, written_html_chunks.join)
      end

      should "keep a paragraph between two tables as its own element" do
        body = "| a | b |\n|---|---|\n| 1 | 2 |\n\nbetween tables\n\n| c | d |\n|---|---|\n| 3 | 4 |\n"

        project_health_to_pdf(@project, body)
        names = Nokogiri::HTML::DocumentFragment.parse(written_html_chunks.join).children.reject(&:text?).map(&:name)

        assert_equal %w[table p table], names
      end

      should "draw the same tables as the screen when a sentence follows a table without a blank line" do
        body = "| a | b |\n|---|---|\n| 1 | 2 |\nright after the table\n"

        project_health_to_pdf(@project, body)

        assert_equal pdf_tables(md_to_html(body)), pdf_tables(written_html_chunks.join)
      end

      should "draw the last row of a body that ends with a table row and no newline" do
        body = "| a | b |\n|---|---|\n| 1 | 2 |\n| last | row |"

        project_health_to_pdf(@project, body)

        assert_equal [ [ "1", "2" ], [ "last", "row" ] ], pdf_tables(written_html_chunks.join).first[:rows]
      end

      should "draw a table without data rows as a header-only table" do
        project_health_to_pdf(@project, "| a | b |\n|---|---|\n")
        table = pdf_tables(written_html_chunks.join).first

        assert_equal [ "a", "b" ], table[:header]
        assert_empty table[:rows]
      end

      should "not truncate long cell text" do
        long = "word " * 20
        project_health_to_pdf(@project, "| a |\n|---|\n| #{long.strip} |\n")

        assert_equal [ [ long.strip ] ], pdf_tables(written_html_chunks.join).first[:rows]
        assert_no_match(/\.\.\./, written_html_chunks.join)
      end

      should "draw rows with different cell counts as the screen does" do
        body = "| a | b | c |\n|---|---|---|\n| 1 | 2 |\n| 1 | 2 | 3 | 4 |\n"

        project_health_to_pdf(@project, body)

        assert_equal pdf_tables(md_to_html(body)), pdf_tables(written_html_chunks.join)
      end

      should "not draw pipe lines inside a code block as a table" do
        body = "```\n| a | b |\n|---|---|\n| 1 | 2 |\n```\n"

        project_health_to_pdf(@project, body)

        assert_raises(ArgumentError) { pdf_tables(written_html_chunks.join) }
        assert_includes written_html_chunks.join, "<pre"
      end
    end

    context "no duplicate or fallback output" do
      setup do
        Redmine::Export::PDF::ITCPDF.prepend(PdfCallRecorder)
        PdfCallRecorder.calls.clear
        PdfCallRecorder.recording = true
      end

      teardown do
        PdfCallRecorder.recording = false
      end

      should "draw each part once and leave no Markdown table line in the text" do
        body = "# Heading Once\n\nParagraph Once\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nTail Once\n"

        pdf = project_health_to_pdf(@project, body)
        text = pdf_text(pdf)
        texts = pdf_text_runs(pdf).map(&:text)

        # The searched region exists: heading, paragraph, table cells and tail
        # are all in the text layer.
        assert_operator texts.size, :>=, 6, "heading, paragraph, table and tail must be drawn"
        %w[Heading\ Once Paragraph\ Once Tail\ Once a b 1 2].each { |word| assert_includes texts, word }

        # The old bug printed the Markdown table lines as plain text, so a run
        # was a line starting with "|" (the separator row "|---|---|" included).
        pipe_runs = texts.select { |run| run.start_with?("|") || run.include?("|---") }
        assert_empty pipe_runs

        # Each part is drawn exactly once.
        %w[Heading Paragraph Tail].each { |word| assert_equal 1, text.scan("#{word} Once").size, word }
      end

      should "hand no blank HTML chunk to the PDF writer, whatever the marker positions are" do
        render_with_charts("{{ai_helper_chart(status, version=12)}}\n\nMiddle\n\n{{ai_helper_chart(open_closed, version=12)}}")

        blanks = written_html_chunks.select { |html| html.strip.empty? }
        assert_empty blanks
      end

      should "let an exception from the Markdown conversion surface without a fallback" do
        stubs(:md_to_html).raises(RuntimeError, "conversion failed")
        ai_helper_logger.expects(:error).never

        error = assert_raises(RuntimeError) { project_health_to_pdf(@project, "text") }
        assert_equal "conversion failed", error.message
      end
    end

    context "positions" do
      setup do
        Redmine::Export::PDF::ITCPDF.prepend(PdfCallRecorder)
        PdfCallRecorder.calls.clear
        PdfCallRecorder.recording = true
      end

      teardown do
        PdfCallRecorder.recording = false
      end

      should "draw headings and tables in the order they are written" do
        body = "# First\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n# Second\n\n| c | d |\n|---|---|\n| 3 | 4 |\n"

        project_health_to_pdf(@project, body)
        nodes = Nokogiri::HTML::DocumentFragment.parse(written_html_chunks.join).children.reject(&:text?)

        assert_equal %w[h1 table h1 table], nodes.map(&:name)
        assert_equal [ "First", "Second" ], nodes.select { |n| n.name == "h1" }.map(&:text)
      end

      should "draw a chart between the tables written before and after it" do
        body = "| a | b |\n|---|---|\n| 1 | 2 |\n\n{{ai_helper_chart(status, version=12)}}\n\n| c | d |\n|---|---|\n| 3 | 4 |\n"

        render_with_charts(body)
        sequence = PdfCallRecorder.calls.map(&:first).select { |name| %i[RDMwriteFormattedCell Rect].include?(name) }

        # The first table's HTML, then the chart's bars (two bars, each drawn
        # filled and bordered), then the second table's HTML.
        assert_equal([ :RDMwriteFormattedCell ] + ([ :Rect ] * 4) + [ :RDMwriteFormattedCell ], sequence)
        assert_equal [ [ "1", "2" ] ], pdf_tables(written_html_chunks.first).first[:rows]
        assert_equal [ [ "3", "4" ] ], pdf_tables(written_html_chunks.last).first[:rows]
      end

      should "draw consecutive directives in order, each at its own marker" do
        body = "{{ai_helper_chart(status, version=12)}}\n\n{{ai_helper_chart(progress, version=12)}}"

        pdf = render_with_charts(body)

        text = pdf_text(pdf)
        assert_includes text, "Issues by Status - 1.0.0"
        assert_includes text, "Not started (3)"
        assert_operator text.index("Issues by Status - 1.0.0"), :<, text.index("Not started (3)"),
                       "the status chart must be drawn before the progress chart"
      end

      should "draw a directive that appears twice once per marker" do
        render_with_charts("{{ai_helper_chart(status, version=12)}}\n\n{{ai_helper_chart(status, version=12)}}")

        assert_equal 8, calls_named(:Rect).length, "two status charts, each with two bars drawn twice"
      end

      should "draw a directive that the scanner left in a fenced code block as body text" do
        body = "```\n{{ai_helper_chart(status, version=12)}}\n```\n"

        render_with_charts(body)

        assert_includes written_html_chunks.join, "{{ai_helper_chart(status, version=12)}}"
        assert_empty calls_named(:Rect)
      end

      should "raise when a chart marker paragraph is lost" do
        directive = RedmineAiHelper::HealthReportChart::Directive.new(type: "status", target_kind: :version, target_value: "12", source: "{{ai_helper_chart(status, version=12)}}")
        stubs(:health_report_html_with_chart_markers).returns([ "<p>no marker here</p>", [ [ "aihelperchartlost", directive ] ] ])

        error = assert_raises(RuntimeError) { project_health_to_pdf(@project, "text") }
        assert_equal "Chart marker paragraph was not rendered in the report body " \
                     "(1 marker(s) left, directive: {{ai_helper_chart(status, version=12)}}, marker: aihelperchartlost)",
                     error.message
      end
    end

    context "elements match the screen" do
      setup do
        Redmine::Export::PDF::ITCPDF.prepend(PdfCallRecorder)
        PdfCallRecorder.calls.clear
        PdfCallRecorder.recording = true
      end

      teardown do
        PdfCallRecorder.recording = false
      end

      should "pass the same element kinds and texts as the screen (Markdown formatting)" do
        assert_pdf_matches_screen
      end

      should "pass the same element kinds and texts as the screen (Textile formatting)" do
        with_settings text_formatting: "textile" do
          assert_pdf_matches_screen
        end
      end

      should "draw the headings as headings and the numbered lists with their numbers in the text layer" do
        text = pdf_text(render_with_charts(ALL_ELEMENTS_BODY)).b

        [ "Heading One", "Heading Two", "Heading Three" ].each { |heading| assert_includes text, heading }
        assert_equal %w[1. 1. 2.], text.scan(/\[\((\d+\.)\)\] TJ/).flatten
      end

      should "keep a directive that is not on a line of its own as text on screen and in the PDF" do
        # The scanner only recognizes a directive on a whole line outside
        # fences, so a directive inside a list item or a quote is plain text
        # for the screen and the PDF alike — neither draws a chart for it.
        body = "- item {{ai_helper_chart(status, version=12)}}\n\n> quote {{ai_helper_chart(progress, version=12)}}\n"
        report = AiHelperHealthReport.new(metrics: CHART_METRICS)

        screen = render_health_report_markdown(body, report: report)
        pdf = render_with_charts(body)

        assert_includes screen, "{{ai_helper_chart(status, version=12)}}"
        assert_includes screen, "{{ai_helper_chart(progress, version=12)}}"
        assert_includes pdf_text(pdf), "{{ai_helper_chart(status, version=12)}}"
        assert_includes pdf_text(pdf), "{{ai_helper_chart(progress, version=12)}}"
        assert_empty calls_named(:Rect)
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
          send(:add_simple_paragraph_to_pdf, @pdf, "This is a paragraph of text.", @left_margin, "L")
        end
      end

      should "handle empty text" do
        assert_nothing_raised do
          send(:add_simple_paragraph_to_pdf, @pdf, "", @left_margin, "L")
        end
      end

      should "place the paragraph further right when the text_align is R" do
        send(:add_simple_paragraph_to_pdf, @pdf, "AlignMarker", @left_margin, "L")
        left_x = pdf_text_runs(@pdf.output).find { |run| run.text == "AlignMarker" }.x

        right_pdf = Redmine::Export::PDF::ITCPDF.new("en")
        right_pdf.add_page
        send(:add_simple_paragraph_to_pdf, right_pdf, "AlignMarker", @left_margin, "R")
        right_x = pdf_text_runs(right_pdf.output).find { |run| run.text == "AlignMarker" }.x

        assert_operator right_x, :>, left_x, "R must place the paragraph further right than L"
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
