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
      assert_no_match(/<script>/, html)
    end
  end
end
