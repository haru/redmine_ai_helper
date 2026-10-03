# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class AiHelperDashboardHelperTest < ActionView::TestCase
  include AiHelperHelper
  include AiHelperDashboardHelper
  include Redmine::I18n

  context "render_health_report_markdown" do
    setup do
      @original_text_formatting = Setting.text_formatting
    end

    teardown do
      Setting.text_formatting = @original_text_formatting
    end

    [ "textile", "common_mark", "" ].each do |formatting|
      should "render Markdown regardless of the #{formatting.inspect} text formatting setting" do
        Setting.text_formatting = formatting

        html = render_health_report_markdown("# Heading\n\n**bold** text")

        assert_includes html, "<h1>Heading</h1>"
        assert_includes html, "<strong>bold</strong>"
      end
    end

    should "linkify bare issue references like the chat rendering does" do
      html = render_health_report_markdown("See #1234 in the report")

      assert_includes html, %(<a href="/issues/1234">#1234</a>)
    end

    should "sanitize script tags included in the body" do
      html = render_health_report_markdown("Safe text\n\n<script>alert('xss')</script>")

      assert_no_match(%r{<script}, html)
    end
  end

  context "ai_helper_markdown_toolbar_heads" do
    setup do
      @original_text_formatting = Setting.text_formatting
      Setting.text_formatting = "textile"
    end

    teardown do
      Setting.text_formatting = @original_text_formatting
    end

    should "emit the CommonMark toolbar assets regardless of the text formatting setting" do
      ai_helper_markdown_toolbar_heads
      heads = content_for(:header_tags)

      assert_includes heads, "jstoolbar/jstoolbar"
      assert_includes heads, "jstoolbar/common_mark"
      assert_includes heads, %(jstoolbar/lang/jstoolbar-#{current_language.to_s.downcase})
      assert_includes heads, "jstoolbar.css"
      assert_includes heads, "wikiImageMimeTypes"
      assert_includes heads, "userHlLanguages"
      assert_not_includes heads, "jstoolbar/textile"
    end

    should "emit the assets only once when called twice" do
      ai_helper_markdown_toolbar_heads
      ai_helper_markdown_toolbar_heads
      heads = content_for(:header_tags)

      assert_equal 1, heads.scan("jstoolbar/common_mark").size
      assert_equal 1, heads.scan("jstoolbar.css").size
    end
  end

  context "health_report_edit_notice_text" do
    setup do
      @report = AiHelperHealthReport.create!(project: Project.find(1), user: User.find(1), health_report: "Body")
    end

    should "return nil for an unedited report" do
      assert_nil health_report_edit_notice_text(@report)
    end

    should "return a plain-text quote line for an edited report" do
      editor = User.find(2)
      @report.update_content("Edited body", editor)

      text = health_report_edit_notice_text(@report)

      assert text.start_with?("> #{l("ai_helper.health_report_edit.edited")}: ")
      assert_includes text, editor.name
      assert_includes text, format_time(@report.last_edited_on)
      assert_no_match(/[<>]/, text.sub(/\A> /, ""))
      assert_not_includes text, "\n"
    end
  end
end
