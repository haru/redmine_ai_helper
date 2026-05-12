# frozen_string_literal: true

# AiHelperHelper module for AI Helper plugin
module AiHelperHelper
  include Redmine::WikiFormatting::CommonMark

  # @api private
  # Matches a bare #NNN issue reference preceded by a non-word character or line start.
  ISSUE_REFERENCE_PATTERN = /(^|[^\w])#(\d+)/.freeze

  # @api private
  # Tags whose text content must not be linkified.
  ISSUE_REFERENCE_EXCLUDED_TAGS = %w[a pre code].freeze

  # Converts a given Markdown text to HTML using the Markdown pipeline.
  # Supports both Redmine 6.1 (MarkdownPipeline) and master (MarkdownFilter) versions.
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    if defined?(MarkdownPipeline)
      MarkdownPipeline.call(text)[:output].to_s.html_safe # rubocop:disable Rails/OutputSafety
    else
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
  # the corresponding Redmine issue page. Uses Nokogiri DOM traversal so that
  # only text nodes outside <a>, <pre>, and <code> subtrees are processed,
  # preventing corruption of attribute values or existing links.
  def linkify_issue_references(html)
    return html if html.nil?

    doc = Nokogiri::HTML::DocumentFragment.parse(html.to_s)

    doc.traverse do |node|
      next unless node.text?
      next if ISSUE_REFERENCE_EXCLUDED_TAGS.include?(node.parent&.name)

      next unless node.content =~ ISSUE_REFERENCE_PATTERN

      new_html = node.content.gsub(ISSUE_REFERENCE_PATTERN) do
        prefix = Regexp.last_match(1)
        id = Regexp.last_match(2)
        %(#{prefix}<a href="#{issue_path(id: id)}">##{id}</a>)
      end

      node.replace(new_html)
    end

    doc.to_s.html_safe # rubocop:disable Rails/OutputSafety
  end
end
