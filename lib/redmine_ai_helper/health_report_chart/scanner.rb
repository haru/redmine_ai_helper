# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/directive"

module RedmineAiHelper
  module HealthReportChart
    # Splits a report body into plain text chunks and chart directives.
    # A chart directive is a single line matching the documented pattern and
    # standing outside fenced code blocks (``` or ~~~). Inline code, list
    # items, quotes and indented code blocks never match because the pattern
    # anchors the line start; lines inside fenced code blocks are excluded by
    # explicit fence tracking.
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
          fence = nil

          lines = markdown.split("\n", -1)
          lines.each_with_index do |line, index|
            newline = index == lines.length - 1 ? "" : "\n"

            if pending_newline
              buffer << "\n"
              pending_newline = false
            end

            if fence
              fence = nil if fence_closes?(line, fence)
              buffer << line << newline
            elsif (opened = opening_fence(line))
              fence = opened
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

        # A fence is closed by a line of the same character, at least as
        # long as the opening, followed only by whitespace.
        def fence_closes?(line, fence)
          line.match?(/\A {0,3}#{Regexp.escape(fence[:char])}{#{fence[:length]},}[ \t]*\z/)
        end
      end
    end
  end
end
