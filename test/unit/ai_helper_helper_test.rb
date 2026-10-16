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

  # The md_to_html output captured before the table class change, with the only
  # prescribed difference applied: <table> became <table class="list">. Every
  # other character, including checked="" disabled="" and the pre-wrapper
  # markup, must stay as it was.
  PINNED_NON_TABLE_HTML = <<~HTML.freeze
<h1>Heading 1</h1>
<h2>Heading 2</h2>
<p>Task list:</p>
<ul class="contains-task-list">
<li class="task-list-item"><input type="checkbox" class="task-list-item-checkbox" checked="" disabled=""> done task</li>
<li class="task-list-item"><input type="checkbox" class="task-list-item-checkbox" disabled=""> open task</li>
</ul>
<div class="pre-wrapper" data-controller="clipboard"><a class="copy-pre-content-link icon-only" title="Copy" data-action="clipboard#copyPre"><svg class="s18 icon-svg" aria-hidden="true"><use href="/assets/icons-0476c1d7.svg#icon--copy-pre-content"></use></svg></a><pre data-clipboard-target="pre"><code class="ruby syntaxhl" data-language="ruby"><span class="nb">puts</span> <span class="s2">"code block"</span>
</code></pre></div>
<div class="markdown-alert markdown-alert-note">
<p class="markdown-alert-title"><svg class="s18 icon-svg" aria-hidden="true"><use href="/assets/icons-0476c1d7.svg#icon--help"></use></svg><span class="icon-label">Note</span></p>
<p>This is an alert.</p>
</div>
<p>Footnote reference<sup><a href="#fn-1" id="fnref-1">1</a></sup>.</p>
<p>See issue #123 for details.</p>
<table class="list">
<thead>
<tr>
<th>none</th>
<th align="left">left</th>
<th align="center">center</th>
<th align="right">right</th>
</tr>
</thead>
<tbody>
<tr>
<td>1</td>
<td align="left">2</td>
<td align="center">3</td>
<td align="right">4</td>
</tr>
<tr>
<td>5</td>
<td align="left">6</td>
<td align="center">7</td>
<td align="right">8</td>
</tr>
</tbody>
</table>
#{' '}
<ol>
<li id="fn-1">
<p>Footnote body. <a href="#fnref-1" aria-label="Back to reference 1">↩</a></p>
</li>
</ol>
#{' '}
  HTML

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

    should "replace the class of a raw HTML table in the body with list" do
      markdown = %(<table class="x"><tr><td>raw</td></tr></table>)
      html = md_to_html(markdown)

      assert_includes html, %(<table class="list">)
      assert_not_includes html, %(class="x")
    end

    should "keep the output identical to the previous implementation except for the table class" do
      html = md_to_html(NON_TABLE_FIXTURE)

      # The heredoc always ends with a newline, but the real output ends with
      # the single space of the footnote separator.
      assert_equal PINNED_NON_TABLE_HTML.chomp, html
      # The alignment hints of th/td must survive (they are part of the pinned string).
      assert_includes html, %(<th align="left">left</th>)
      assert_includes html, %(<th align="center">center</th>)
      assert_includes html, %(<th align="right">right</th>)
      assert_includes html, %(<td align="right">4</td>)
    end
  end

  context "md_to_html Redmine 6.x pipeline branch" do
    teardown do
      AiHelperHelper.send(:remove_const, :MarkdownPipeline) if AiHelperHelper.const_defined?(:MarkdownPipeline)
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

      assert_raises(ArgumentError) do
        md_to_html("text")
      end
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
end
