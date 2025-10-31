# frozen_string_literal: true
# AiHelperHelper module for AI Helper plugin
# frozen_string_literal: true
# AiHelperHelper module for AI Helper plugin
module AiHelperHelper
  include Redmine::WikiFormatting::CommonMark

  # Converts a given Markdown text to HTML using the Markdown pipeline.
  # Supports both Redmine 6.1 (MarkdownPipeline) and master (MarkdownFilter) versions.
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")

    if defined?(MarkdownPipeline)
      # Redmine 6.1 and earlier
      MarkdownPipeline.call(text)[:output].to_s.html_safe
    else
      # Redmine master (future 7.x)
      html = MarkdownFilter.new(text, PIPELINE_CONFIG).call
      fragment = Redmine::WikiFormatting::HtmlParser.parse(html)
      SANITIZER.call(fragment)
      SCRUBBERS.each do |scrubber|
        fragment.scrub!(scrubber)
      end
      fragment.to_s.html_safe
    end
  end
end
