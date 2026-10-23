# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/directive"

module RedmineAiHelper
  module HealthReportChart
    # Splits a report body into plain text chunks and chart directives.
    # A chart directive is a single line matching the documented pattern and
    # standing outside fenced code blocks (``` or ~~~) and outside CommonMark
    # HTML blocks of types 1-5, whose blocks are not ended by a blank line
    # (<pre>, <script>, <style>, <textarea>, <!--, <?, <!DOCTYPE, <![CDATA[);
    # a directive line inside them is raw HTML content, never a paragraph, so
    # it stays in the text. Inline code, list items, quotes and indented code
    # blocks never match because the pattern anchors the line start; lines
    # inside fenced code blocks are excluded by explicit fence tracking.
    module Scanner
      # A directive occupies a whole line: up to three leading spaces (four
      # would be an indented code block), the directive itself, then only
      # spaces/tabs before the end of the line.
      DIRECTIVE_PATTERN = /\A {0,3}\{\{ai_helper_chart\((?<args>[^()\n]*)\)\}\}[ \t]*\z/
      # A valid version target: version=<digits>.
      VERSION_TARGET_PATTERN = /\Aversion\s*=\s*(\d+)\z/
      # A valid period target: period=<lowercase key>.
      PERIOD_TARGET_PATTERN = /\Aperiod\s*=\s*([a-z_]+)\z/
      # An opening backtick fence: up to three spaces, then 3+ backticks
      # whose info string contains no backtick.
      FENCE_OPEN_BACKTICK_PATTERN = /\A {0,3}(`{3,})[^`]*\z/
      # An opening tilde fence: up to three spaces, then 3+ tildes.
      FENCE_OPEN_TILDE_PATTERN = /\A {0,3}(~{3,})/
      # CommonMark HTML block type 1: <script>, <pre>, <style> or <textarea>
      # (case-insensitive), followed by whitespace, ">" or the end of the
      # line. The block ends only at its own closing tag.
      HTML_BLOCK_TYPE1_PATTERN = /\A {0,3}<(script|pre|style|textarea)(?=[ \t>]|\z)/i
      # CommonMark HTML block type 2: an HTML comment.
      HTML_BLOCK_TYPE2_PATTERN = /\A {0,3}<!--/
      # CommonMark HTML block type 3: a processing instruction.
      HTML_BLOCK_TYPE3_PATTERN = /\A {0,3}<\?/
      # CommonMark HTML block type 5: a CDATA section.
      HTML_BLOCK_TYPE5_PATTERN = /\A {0,3}<!\[CDATA\[/
      # CommonMark HTML block type 4: a declaration like <!DOCTYPE html>.
      HTML_BLOCK_TYPE4_PATTERN = /\A {0,3}<![A-Za-z]/

      class << self
        # Split the body into text chunks and Directive objects, preserving
        # the original order. A body without chart directives returns
        # [markdown] (a single string equal to the input).
        # @param markdown [String] the report body
        # @return [Array<String, RedmineAiHelper::HealthReportChart::Directive>]
        # @raise [ArgumentError] when markdown is not a String
        def split(markdown)
          raise ArgumentError, "markdown must be a String" unless markdown.is_a?(String)
          return [ markdown ] if markdown.empty?

          parts = []
          buffer = +""
          pending_newline = false
          block = nil

          lines = markdown.split("\n", -1)
          lines.each_with_index do |line, index|
            newline = index == lines.length - 1 ? "" : "\n"

            if pending_newline
              buffer << "\n"
              pending_newline = false
            end

            if block
              block = nil if block_closes?(line, block)
              buffer << line << newline
            elsif (opened = opening_block(line))
              block = opened
              # An HTML block's opening line may already carry its end
              # condition, as in "<pre>code</pre>" or "<!-- comment -->". A
              # fence's opening line always matches its own close pattern,
              # so it never closes the fence it opens.
              block = nil if opened[:kind] == :html && html_block_closes?(line, opened)
              buffer << line << newline
            elsif (match = line.match(DIRECTIVE_PATTERN))
              parts << buffer unless buffer.empty?
              buffer = +""
              parts << build_directive(match[:args], line.strip)
              pending_newline = newline != ""
            else
              buffer << line << newline
            end
          end

          parts << buffer unless buffer.empty?
          parts
        end

        private

        # Build a Directive from the directive's argument string and its
        # source line. Arguments that do not split into "type, target" with
        # a syntactically valid target produce a Directive with a nil
        # target_kind (invalid arguments).
        def build_directive(args, source)
          segments = args.split(",", -1).map(&:strip)
          unless segments.length == 2
            return Directive.new(type: segments.first.to_s, target_kind: nil, target_value: nil, source: source)
          end

          kind, value = parse_target(segments[1])
          Directive.new(type: segments[0], target_kind: kind, target_value: value, source: source)
        end

        # Parse the target argument into [target_kind, target_value].
        # @return [Array(Symbol, String), Array(nil, nil)]
        def parse_target(target)
          if (match = target.match(VERSION_TARGET_PATTERN))
            [ :version, match[1] ]
          elsif (match = target.match(PERIOD_TARGET_PATTERN))
            [ :period, match[1] ]
          else
            [ nil, nil ]
          end
        end

        # @return [Hash, nil] {char:, length:} when the line opens a fence
        def opening_fence(line)
          if (match = line.match(FENCE_OPEN_BACKTICK_PATTERN))
            { char: "`", length: match[1].length }
          elsif (match = line.match(FENCE_OPEN_TILDE_PATTERN))
            { char: "~", length: match[1].length }
          end
        end

        # @return [Hash, nil] the block the line opens: a fenced code block
        #   ({kind: :fence, char:, length:}) or an HTML block of type 1-5
        #   ({kind: :html, end_pattern:})
        def opening_block(line)
          fence = opening_fence(line)
          return { kind: :fence, char: fence[:char], length: fence[:length] } if fence

          html = opening_html_block(line)
          return { kind: :html, end_pattern: html[:end_pattern] } if html

          nil
        end

        # A block ends when its line carries the end condition: a fence by a
        # line of the same character at least as long as the opening, an HTML
        # block of type 1-5 by its end pattern (never at a blank line).
        # @param line [String] the line inside the block
        # @param block [Hash] the open block state from opening_block
        # @return [Boolean] whether the line ends the block
        # @raise [ArgumentError] when the block state has an unknown kind
        def block_closes?(line, block)
          case block[:kind]
          when :fence then fence_closes?(line, block)
          when :html then html_block_closes?(line, block)
          else raise ArgumentError, "unknown block kind: #{block[:kind].inspect}"
          end
        end

        # A fence is closed by a line of the same character, at least as
        # long as the opening, followed only by whitespace.
        def fence_closes?(line, fence)
          line.match?(/\A {0,3}#{Regexp.escape(fence[:char])}{#{fence[:length]},}[ \t]*\z/)
        end

        # @return [Hash, nil] {end_pattern:} when the line opens an HTML
        #   block of type 1-5; the Regexp matches the line that ends it
        def opening_html_block(line)
          if (match = line.match(HTML_BLOCK_TYPE1_PATTERN))
            { end_pattern: /<\/#{match[1].downcase}>/i }
          elsif line.match?(HTML_BLOCK_TYPE2_PATTERN)
            { end_pattern: /-->/ }
          elsif line.match?(HTML_BLOCK_TYPE3_PATTERN)
            { end_pattern: /\?>/ }
          elsif line.match?(HTML_BLOCK_TYPE5_PATTERN)
            { end_pattern: /\]\]>/ }
          elsif line.match?(HTML_BLOCK_TYPE4_PATTERN)
            { end_pattern: />/ }
          end
        end

        # An HTML block of type 1-5 ends when the line contains its end
        # condition (a closing tag, -->, ?>, > or ]]>, depending on the
        # type) — never at a blank line.
        def html_block_closes?(line, html_block)
          line.match?(html_block[:end_pattern])
        end
      end
    end
  end
end
