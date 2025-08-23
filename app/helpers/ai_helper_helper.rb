# frozen_string_literal: true
# AiHelperHelper module for AI Helper plugin
module AiHelperHelper
  include Redmine::WikiFormatting::CommonMark

  # Converts a given Markdown text to HTML using the Markdown pipeline.
  def md_to_html(text)
    text = text.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    MarkdownPipeline.call(text)[:output].to_s.html_safe
  end

end
