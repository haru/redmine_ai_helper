# frozen_string_literal: true

require "zip"
require "redmine_ai_helper/health_report_chart/scanner"
require "redmine_ai_helper/health_report_chart/resolver"
require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/svg_renderer"

module RedmineAiHelper
  module HealthReportChart
    # Builds the Markdown export zip: <base>.md plus charts/chart-<n>.svg,
    # where n numbers only the drawable charts, in order of appearance
    # (R-010); a directive that cannot be drawn gets no file. Drawable
    # directives become image references; the others become a one-line
    # blockquote with the reason.
    module MarkdownArchive
      class << self
        # @param markdown [String] the report body (with chart directives)
        # @param resolver [Resolver] resolves directives to charts
        # @param base_name [String] file name without extension
        # @return [String] the zip file as a binary string
        # @raise [ArgumentError] when resolver is not a Resolver
        def build(markdown, resolver:, base_name:)
          raise ArgumentError, "resolver must be a Resolver" unless resolver.is_a?(Resolver)

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
            case part
            when String
              trim_text(part, index.zero? ? nil : parts[index - 1], parts[index + 1])
            when Directive
              yield part
            else
              raise ArgumentError, "expected a String or a Directive, got #{part.class}"
            end
          end
          result = pieces.reject(&:empty?).join("\n\n")
          markdown.end_with?("\n") && !result.end_with?("\n") ? "#{result}\n" : result
        end

        private

        # True only for a Directive part. nil is the out-of-range neighbor
        # (the body starts or ends with a directive), not a part.
        # @raise [ArgumentError] when the part is neither a String, a
        #   Directive nor nil
        def directive_part?(part)
          case part
          when Directive then true
          when String, nil then false
          else raise ArgumentError, "expected a String, a Directive or nil, got #{part.class}"
          end
        end

        # Drop the newlines that touched a directive line; the join adds the
        # blank lines back.
        def trim_text(text, previous, following)
          text = text.sub(/\A\n+/, "") if directive_part?(previous)
          text = text.sub(/\n+\z/, "") if directive_part?(following)
          text
        end

        def replacement(resolved, svgs)
          case resolved
          when Unavailable
            "> #{resolved.message}"
          when Chart
            svgs << SvgRenderer.render(resolved)
            "![#{escape_title(resolved.title)}](charts/chart-#{svgs.length}.svg)"
          else
            raise ArgumentError, "expected a Chart or an Unavailable, got #{resolved.class}"
          end
        end

        def escape_title(title)
          title.gsub(/[\[\]\\]/) { |char| "\\#{char}" }
        end
      end
    end
  end
end
