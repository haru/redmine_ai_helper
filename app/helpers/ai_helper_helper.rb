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
  # Supports both Redmine 6.x (MarkdownPipeline) and 7.x and later (MarkdownFilter).
  # Every <table> of the output gets Redmine's standard "list" class so that the
  # standard table styling applies; the column alignment is then decided by the
  # container rules in ai_helper.css.
  # @param text [String] The Markdown text.
  # @return [ActiveSupport::SafeBuffer] The sanitized HTML.
  # @raise [ArgumentError] If MarkdownPipeline#call does not return a
  #   Nokogiri::XML::DocumentFragment in :output (Redmine 6.x only).
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    fragment = defined?(MarkdownPipeline) ? pipeline_fragment(text) : filter_fragment(text)
    set_list_class_on_tables(fragment)
    fragment.to_s.html_safe # rubocop:disable Rails/OutputSafety
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

  # Renders the text with Redmine 6.x's MarkdownPipeline (already sanitized).
  # @api private
  # @param text [String] The Markdown text.
  # @return [Nokogiri::XML::DocumentFragment] The sanitized fragment.
  # @raise [ArgumentError] If the pipeline output is not a document fragment.
  def pipeline_fragment(text)
    output = MarkdownPipeline.call(text)[:output]
    unless output.is_a?(Nokogiri::XML::DocumentFragment)
      raise ArgumentError, "MarkdownPipeline#call must return a Nokogiri::XML::DocumentFragment in :output, but got #{output.class}"
    end

    output
  end

  # Renders the text with Redmine 7.x's MarkdownFilter and sanitizes the result.
  # @api private
  # @param text [String] The Markdown text.
  # @return [Nokogiri::XML::DocumentFragment] The sanitized fragment.
  def filter_fragment(text)
    html = MarkdownFilter.new(text, PIPELINE_CONFIG).call
    fragment = Redmine::WikiFormatting::HtmlParser.parse(html)
    SANITIZER.call(fragment)
    SCRUBBERS.each do |scrubber|
      fragment.scrub!(scrubber)
    end
    fragment
  end

  # Sets Redmine's standard "list" class on every <table> of the Nokogiri
  # fragment, overwriting any existing class. It runs after sanitization
  # because the sanitizer does not allow a class on <table> and would strip
  # "list"; overwriting also means a class written in the source body never
  # reaches the output. The fragment is changed in place instead of being
  # serialized and re-parsed, because a re-parse alters the markup outside the
  # tables (task-list items, div.pre-wrapper, disabled="").
  # @api private
  # @param fragment [Nokogiri::XML::DocumentFragment] The sanitized fragment.
  # @return [void]
  def set_list_class_on_tables(fragment)
    fragment.css("table").each do |table|
      table["class"] = "list"
    end
  end

  def excluded_ancestor?(node)
    node.ancestors.any? { |a| ISSUE_REFERENCE_EXCLUDED_TAGS.include?(a.name) }
  end
end
