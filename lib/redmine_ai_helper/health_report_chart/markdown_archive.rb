# frozen_string_literal: true

require "zip"
require "redmine_ai_helper/health_report_chart/scanner"
require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/svg_renderer"

module RedmineAiHelper
  module HealthReportChart
    # Builds the Markdown export zip: <base>.md plus charts/chart-<n>.svg,
    # where n is the directive's order of appearance (R-010). Directives that
    # can be drawn become image references; those that cannot become a
    # one-line blockquote with the reason.
    module MarkdownArchive
      class << self
        # @param markdown [String] the report body (with chart directives)
        # @param resolver [Resolver] resolves directives to charts
        # @param base_name [String] file name without extension
        # @return [String] the zip file as a binary string
        def build(markdown, resolver:, base_name:)
          svgs = []
          document = replace_directives(markdown) { |directive| replacement(resolver.resolve(directive), svgs) }

          buffer = Zip::OutputStream.write_buffer do |zip|
            zip.put_next_entry("#{base_name}.md")
            zip.write(document)
            svgs.each_with_index do |svg, index|
              zip.put_next_entry("charts/chart-#{index + 1}.svg")
              zip.write(svg)
            end
          end
          buffer.string
        end

        # Replace only the directive lines with the block's return value and
        # surround each replacement with blank lines. A body without
        # directives is returned unchanged.
        # @param markdown [String] the report body
        # @yieldparam directive [Directive] a chart directive found in the body
        # @yieldreturn [String] the Markdown that replaces the directive line
        # @return [String] the rewritten body
        def replace_directives(markdown)
          parts = Scanner.split(markdown)
          return markdown if parts.length == 1 && parts.first.is_a?(String)

          pieces = parts.each_with_index.map do |part, index|
            next trim_text(part, parts[index - 1], parts[index + 1]) if part.is_a?(String)

            yield part
          end
          result = pieces.reject(&:empty?).join("\n\n")
          markdown.end_with?("\n") && !result.end_with?("\n") ? "#{result}\n" : result
        end

        private

        # Drop the newlines that touched a directive line; the join adds the
        # blank lines back.
        def trim_text(text, previous, following)
          text = text.sub(/\A\n+/, "") if previous.is_a?(Directive)
          text = text.sub(/\n+\z/, "") if following.is_a?(Directive)
          text
        end

        def replacement(resolved, svgs)
          return "> #{resolved.message}" if resolved.is_a?(Unavailable)

          svgs << SvgRenderer.render(resolved)
          "![#{escape_title(resolved.title)}](charts/chart-#{svgs.length}.svg)"
        end

        def escape_title(title)
          title.gsub(/[\[\]\\]/) { |char| "\\#{char}" }
        end
      end
    end
  end
end
