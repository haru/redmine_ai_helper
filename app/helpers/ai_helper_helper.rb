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
      next if excluded_ancestor?(node)

      next unless node.content =~ ISSUE_REFERENCE_PATTERN

      parts = node.content.split(ISSUE_REFERENCE_PATTERN)
      ndoc = doc.document
      replacement = Nokogiri::HTML::DocumentFragment.new(ndoc)
      replacement << Nokogiri::XML::Text.new(parts[0], ndoc) if parts[0].present?

      i = 1
      while i < parts.length
        prefix = parts[i]
        id = parts[i + 1]
        after_text = parts[i + 2]

        replacement << Nokogiri::XML::Text.new(prefix, ndoc)
        link = Nokogiri::XML::Node.new("a", ndoc)
        link["href"] = issue_path(id: id)
        link.content = "##{id}"
        replacement << link
        replacement << Nokogiri::XML::Text.new(after_text, ndoc) if after_text.present?

        i += 3
      end

      node.replace(replacement)
    end

    doc.to_s.html_safe # rubocop:disable Rails/OutputSafety
  end

  private

  def excluded_ancestor?(node)
    node.ancestors.any? { |a| ISSUE_REFERENCE_EXCLUDED_TAGS.include?(a.name) }
  end
end
