require File.expand_path("../../test_helper", __FILE__)

class AiHelperHelperTest < ActionView::TestCase
  include AiHelperHelper

  def test_md_to_html
    markdown_text = "# Hello World\nThis is a test."
    expected_html = "<h1>Hello World</h1>\n<p>This is a test.</p>"

    assert_equal expected_html, md_to_html(markdown_text)
  end

  def test_md_to_html_with_invalid_characters
    markdown_text = "# Hello World\xC2\nThis is a test."
    expected_html = "<h1>Hello World</h1>\n<p>This is a test.</p>"

    assert_equal expected_html, md_to_html(markdown_text)
  end

  # Fixture covering the non-table elements whose rendering must not change:
  # headings, a task list, a code block (div.pre-wrapper), an alert, a footnote,
  # an issue reference and a table with column alignments.
  NON_TABLE_FIXTURE = <<~MD.freeze
    # Heading 1
    ## Heading 2

    Task list:
    - [x] done task
    - [ ] open task

    ```ruby
    puts "code block"
    ```

    > [!NOTE]
    > This is an alert.

    Footnote reference[^1].

    [^1]: Footnote body.

    See issue #123 for details.

    | none | left | center | right |
    |------|:-----|:------:|------:|
    | 1    | 2    | 3      | 4     |
    | 5    | 6    | 7      | 8     |
  MD

  # Renders +text+ the way md_to_html did before the table class was added:
  # same pipeline, same sanitization, no class on the tables. Built from the
  # running Redmine so that the comparison does not depend on Redmine's
  # asset digests or version-specific markup.
  def render_without_table_class(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    if defined?(MarkdownPipeline)
      MarkdownPipeline.call(text)[:output].to_s
    else
      html = MarkdownFilter.new(text, PIPELINE_CONFIG).call
      fragment = Redmine::WikiFormatting::HtmlParser.parse(html)
      SANITIZER.call(fragment)
      SCRUBBERS.each { |scrubber| fragment.scrub!(scrubber) }
      fragment.to_s
    end
  end

  context "md_to_html tables" do
    should "add the list class to the rendered table" do
      html = md_to_html("| none |\n|------|\n| 1    |")

      assert_includes html, %(<table class="list">)
      assert_equal 1, html.scan(%(<table class="list">)).size
    end

    should "add the list class to nested tables as well" do
      markdown = %(<table><tr><td>outer<table><tr><td>inner</td></tr></table></td></tr></table>)
      html = md_to_html(markdown)

      assert_equal 2, html.scan(%(<table class="list">)).size
    end

    should "return an html_safe string" do
      assert md_to_html("| none |\n|------|\n| 1    |").html_safe?
    end

    should "set the class of a raw HTML table in the body to exactly list" do
      markdown = %(<table class="list x"><tr><td>raw</td></tr></table>)
      html = md_to_html(markdown)

      assert_includes html, %(<table class="list">)
      assert_not_includes html, "list x"
    end

    should "keep the output identical to the previous implementation except for the table class" do
      baseline = render_without_table_class(NON_TABLE_FIXTURE)
      html = md_to_html(NON_TABLE_FIXTURE)

      # The searched region must exist: the fixture contains a table with alignments.
      assert_includes baseline, "<table>"
      assert_includes baseline, %(<th align="center">center</th>)
      assert_equal baseline.gsub("<table>", %(<table class="list">)), html
      # The alignment hints of th/td must survive.
      assert_includes html, %(<th align="left">left</th>)
      assert_includes html, %(<th align="right">right</th>)
      assert_includes html, %(<td align="right">4</td>)
    end
  end

  context "md_to_html Redmine 6.x pipeline branch" do
    teardown do
      AiHelperHelper.send(:remove_const, :MarkdownPipeline) if AiHelperHelper.const_defined?(:MarkdownPipeline, false)
    end

    should "add the list class to tables when the pipeline returns a document fragment" do
      AiHelperHelper.const_set(:MarkdownPipeline, Class.new do
        def self.call(_text)
          { output: Nokogiri::HTML::DocumentFragment.parse(%(<table><tr><td>cell</td></tr></table>)) }
        end
      end)

      assert_includes md_to_html("text"), %(<table class="list">)
    end

    should "raise when the pipeline output is not a document fragment" do
      AiHelperHelper.const_set(:MarkdownPipeline, Class.new do
        def self.call(_text)
          { output: %(<table><tr><td>cell</td></tr></table>) }
        end
      end)

      error = assert_raises(ArgumentError) { md_to_html("text") }
      assert_match(/but got String/, error.message)
    end

    should "raise when the pipeline output is missing" do
      AiHelperHelper.const_set(:MarkdownPipeline, Class.new do
        def self.call(_text)
          {}
        end
      end)

      error = assert_raises(ArgumentError) { md_to_html("text") }
      assert_match(/but got NilClass/, error.message)
    end
  end

  context "linkify_issue_references" do
    setup do
      @original_relative_url_root = Redmine::Utils.relative_url_root
      @original_script_name = Rails.application.routes.default_url_options[:script_name]
    end

    teardown do
      Redmine::Utils.relative_url_root = @original_relative_url_root
      Rails.application.routes.default_url_options[:script_name] = @original_script_name
    end

    should "linkify bare #N after whitespace" do
      html = linkify_issue_references("<p>See #1234 please</p>")
      assert_includes html, %(<a href="/issues/1234">#1234</a>)
    end

    should "linkify bare #N at start of string" do
      html = linkify_issue_references("#1234 body")
      assert_includes html, %(<a href="/issues/1234">#1234</a>)
    end

    should "linkify multiple issue references in the same string" do
      html = linkify_issue_references("<p>See #1 and #2 and #1 again</p>")
      assert_equal 2, html.scan(%(<a href="/issues/1">#1</a>)).size
      assert_equal 1, html.scan(%(<a href="/issues/2">#2</a>)).size
    end

    should "not linkify when preceded by word character" do
      assert_equal "abc#1234", linkify_issue_references("abc#1234")
      assert_equal "v1.0#1234", linkify_issue_references("v1.0#1234")
      assert_equal "my_var#1234", linkify_issue_references("my_var#1234")
    end

    should "not linkify inside existing <a> tag" do
      input = %(<a href="/issues/1234">#1234</a>)
      assert_equal input, linkify_issue_references(input)
    end

    should "not linkify inside <pre> block" do
      input = "<pre>See #1234 here</pre>"
      assert_equal input, linkify_issue_references(input)
    end

    should "not linkify inside <code> block" do
      input = "<code>See #1234 here</code>"
      assert_equal input, linkify_issue_references(input)
    end

    should "not linkify when # is followed by non-digit" do
      assert_equal "#TODO", linkify_issue_references("#TODO")
      assert_equal "#general", linkify_issue_references("#general")
    end

    should "respect relative_url_root when generating href" do
      Redmine::Utils.relative_url_root = "/redmine"
      Rails.application.routes.default_url_options[:script_name] = "/redmine"
      html = linkify_issue_references("See #1234")
      assert_includes html, %(<a href="/redmine/issues/1234">#1234</a>)
    end

    should "return html_safe string" do
      result = linkify_issue_references("See #1234")
      assert result.html_safe?
    end

    should "not double-link content already inside existing markdown-rendered link" do
      input = %(<p>Old: <a href="/issues/1234">#1234</a>, New: #5678</p>)
      html = linkify_issue_references(input)
      assert_equal 1, html.scan(%(<a href="/issues/1234">#1234</a>)).size
      assert_includes html, %(<a href="/issues/5678">#5678</a>)
    end

    should "not linkify #NNN inside HTML attribute values" do
      input = %(<img alt="#1234" src="photo.jpg">)
      html = linkify_issue_references(input)
      assert_includes html, 'alt="#1234"'
      assert_no_match(/<a href.*>#1234/, html)
    end

    should "not linkify #NNN inside nested element within <a>" do
      input = %(<a href="/issues/1234"><span>#1234</span></a>)
      html = linkify_issue_references(input)
      assert_equal input, html
    end

    should "not linkify #NNN inside nested element within <pre>" do
      input = "<pre><span>#1234</span></pre>"
      html = linkify_issue_references(input)
      assert_equal input, html
    end

    should "preserve escaped entities in text without injecting markup" do
      input = "<p>&lt;script&gt; #1234 &lt;/script&gt;</p>"
      html = linkify_issue_references(input)
      assert_includes html, %(<a href="/issues/1234">#1234</a>)
      assert_no_match(/<script>/i, html)
    end
  end

  context "#health_report_html_with_chart_markers" do
    should "return the plain Markdown HTML and no markers when the body has no chart directive" do
      text = "# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nSee #12"
      parts = RedmineAiHelper::HealthReportChart::Scanner.split(text)

      html, markers = health_report_html_with_chart_markers(parts)

      # Concrete expectations instead of recomputing the implementation's
      # expression: the table is rendered (with the list class), and the bare
      # issue reference is linkified.
      assert_empty markers
      assert_includes html, "<h1>Title</h1>"
      assert_includes html, %(<table class="list">)
      assert_includes html, %(<a href="/issues/12">#12</a>)
    end

    should "replace each chart directive with a marker paragraph in body order" do
      text = "Intro\n\n{{ai_helper_chart(status, version=12)}}\n\nMiddle\n\n{{ai_helper_chart(progress, version=12)}}\n\nEnd"
      parts = RedmineAiHelper::HealthReportChart::Scanner.split(text)
      directives = parts.grep(RedmineAiHelper::HealthReportChart::Directive)
      assert_equal 2, directives.size

      html, markers = health_report_html_with_chart_markers(parts)

      assert_equal directives, markers.map(&:last)
      markers.each do |marker, _directive|
        assert_match(/\Aaihelperchart[0-9a-f]{24}\z/, marker)
        assert_equal 1, Nokogiri::HTML::DocumentFragment.parse(html).xpath("./p[text()='#{marker}']").size
      end
      assert_equal markers.map(&:first), html.scan(/aihelperchart[0-9a-f]{24}/)
    end

    should "render tables separated by a blank line as separate tables" do
      text = "| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n\n| x | y |\n|---|---|\n| 4 | 5 |\n"
      parts = RedmineAiHelper::HealthReportChart::Scanner.split(text)

      html, = health_report_html_with_chart_markers(parts)

      assert_equal 2, Nokogiri::HTML::DocumentFragment.parse(html).css("table").size
    end

    should "raise ArgumentError for a part that is neither a String nor a Directive" do
      assert_raises(ArgumentError) { health_report_html_with_chart_markers([ "text", 42 ]) }
    end
  end
end
