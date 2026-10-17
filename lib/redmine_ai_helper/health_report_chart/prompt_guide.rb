# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/resolver"

module RedmineAiHelper
  module HealthReportChart
    # Builds the English instructions that tell the LLM how to place chart
    # directives in a health report (FR-004, FR-005). The LLM only chooses
    # the chart type and its position; the values are drawn from the stored
    # metrics at display time, so it is told not to copy the numbers into
    # the text and to write one or two sentences that interpret each chart
    # for the reader instead.
    module PromptGuide
      # The instruction used when the report has no chartable targets.
      NO_TARGETS = "No chart can be drawn for this report. Do not write any chart directives."

      class << self
        # @param resolver [Resolver] resolver built from the report's metrics
        # @return [String] the guide text to pass as the chart_guide prompt variable
        # @raise [ArgumentError] when resolver is not a Resolver
        def build(resolver)
          raise ArgumentError, "resolver must be a Resolver" unless resolver.is_a?(Resolver)

          I18n.with_locale(:en) do
            targets = resolver.targets
            next NO_TARGETS if targets.empty?

            [ syntax_lines, type_lines, target_lines(targets) ].flatten.join("\n")
          end
        end

        private

        def syntax_lines
          [
            "You can place charts in the report. Write a chart directive on a single line, surrounded by blank lines:",
            "{{ai_helper_chart(<type>, version=<id>)}} or {{ai_helper_chart(<type>, period=<key>)}}",
            "Do not write a directive inside tables, lists, or code blocks.",
            "The chart itself shows the values, so never restate the full breakdown of numbers in the text.",
            "Write one or two sentences before or after each chart that say what it shows to the reader " \
            "(for example a skew, a bottleneck, or the progress made). " \
            "Quote only the one or two figures that the interpretation needs; the chart shows the rest."
          ]
        end

        def type_lines
          [ "Available types:" ] + ChartType.map { |key, definition| "- #{key}: #{I18n.t(definition[:title_key])}" }
        end

        def target_lines(targets)
          [ "Available targets:" ] + targets.map { |target| "- #{target.identifier} (#{target.display_name})" }
        end
      end
    end
  end
end
