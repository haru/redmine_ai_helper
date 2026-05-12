# frozen_string_literal: true

# AiHelperHelper module for AI Helper plugin
module AiHelperHelper
  include Redmine::WikiFormatting::CommonMark

  ISSUE_REFERENCE_MASK_PATTERN = /<a\b[^>]*>.*?<\/a>|<pre\b[^>]*>.*?<\/pre>|<code\b[^>]*>.*?<\/code>/mi.freeze
  ISSUE_REFERENCE_PATTERN = /(^|[^\w])#(\d+)/.freeze
  ISSUE_REFERENCE_MASK_BOUNDARY = "\u0001"
  ISSUE_REFERENCE_MASK_RESTORE_PATTERN = /\u0001AIH_MASK_(\d+)\u0001/.freeze

  # Converts a given Markdown text to HTML using the Markdown pipeline.
  # Supports both Redmine 6.1 (MarkdownPipeline) and master (MarkdownFilter) versions.
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    if defined?(MarkdownPipeline)
      # Redmine 6.1 and earlier
      MarkdownPipeline.call(text)[:output].to_s.html_safe # rubocop:disable Rails/OutputSafety
    else
      # Redmine master (future 7.x)
      html = MarkdownFilter.new(text, PIPELINE_CONFIG).call
      fragment = Redmine::WikiFormatting::HtmlParser.parse(html)
      SANITIZER.call(fragment)
      SCRUBBERS.each do |scrubber|
        fragment.scrub!(scrubber)
      end
      fragment.to_s.html_safe # rubocop:disable Rails/OutputSafety
    end
  end

  # Convert bare "#1234" patterns in an HTML string into anchor tags pointing to
  # the corresponding Redmine issue page. Mirrors the frontend behavior in
  # assets/javascripts/ai_helper_markdown_parser.js so that, after the chat is
  # re-rendered by the server on streaming completion, the same issue links
  # remain clickable. Respects Redmine's relative_url_root via issue_path.
  def linkify_issue_references(html)
    return html if html.nil?

    masks = []
    boundary = ISSUE_REFERENCE_MASK_BOUNDARY
    masked = html.to_s.gsub(ISSUE_REFERENCE_MASK_PATTERN) do |match|
      token = "#{boundary}AIH_MASK_#{masks.length}#{boundary}"
      masks << match
      token
    end

    masked = masked.gsub(ISSUE_REFERENCE_PATTERN) do
      prefix = Regexp.last_match(1)
      id = Regexp.last_match(2)
      %(#{prefix}<a href="#{issue_path(id: id)}">##{id}</a>)
    end

    masked.gsub(ISSUE_REFERENCE_MASK_RESTORE_PATTERN) { masks[Regexp.last_match(1).to_i] }.html_safe # rubocop:disable Rails/OutputSafety
  end
end
