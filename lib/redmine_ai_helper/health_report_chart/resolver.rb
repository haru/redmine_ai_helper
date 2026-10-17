# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/chart"
require "redmine_ai_helper/health_report_chart/directive"
require "redmine/i18n"

module RedmineAiHelper
  module HealthReportChart
    # Resolves chart directives into drawable Chart objects (or Unavailable
    # reasons) from the metrics JSON stored with a report. The stored metrics
    # are the only source of the values; the live project state is never
    # queried. Parsing happens once per resolver instance, and only
    # JSON::ParserError is turned into the metrics_unavailable reason (R-001).
    class Resolver
      include Redmine::I18n

      # The stored period_name to directive key mapping (R-003). Repository
      # periods have no issue statistics, so they are deliberately absent.
      PERIOD_NAME_TO_KEY = {
        "Last 1 Week" => "last_week",
        "Last 1 Month" => "last_month",
        "All Time Analysis" => "all_time",
        "Recent Activity" => "recent"
      }.freeze

      # The maximum number of items before grouping the remainder into
      # "others" (7 items = top 6 + others).
      MAX_ITEMS = Chart::MAX_ITEMS

      # A target that can be addressed by a chart directive, built from the
      # stored metrics. Shown in the edit-form help and the LLM guide.
      Target = Data.define(:identifier, :display_name) do
        # @param identifier [String] non-empty "kind=value" expression
        # @param display_name [String] non-empty display name
        # @raise [ArgumentError] when an attribute violates the invariants
        def initialize(identifier:, display_name:)
          raise ArgumentError, "identifier must be a non-empty String" unless identifier.is_a?(String) && !identifier.empty?
          raise ArgumentError, "display_name must be a non-empty String" unless display_name.is_a?(String) && !display_name.empty?

          super
        end
      end

      # @param metrics_json [String, nil] the stored metrics JSON; nil means
      #   the body has no stored metrics
      # @param comparison [Boolean] true for a comparison report body
      # @raise [ArgumentError] when metrics_json is neither a String nor nil
      def initialize(metrics_json, comparison: false)
        @comparison_mode = comparison
        @data =
          case metrics_json
          when String then parse_metrics(metrics_json)
          when nil then nil
          else raise ArgumentError, "metrics_json must be a String or nil"
          end
      end

      # A resolver for comparison report bodies: every directive resolves to
      # the +comparison+ reason, whatever the arguments and metrics are.
      # @return [Resolver]
      def self.comparison
        new(nil, comparison: true)
      end

      # The localized message shown in place of a chart directive in a
      # comparison report.
      # @return [String]
      def self.comparison_message
        comparison.send(:unavailable, :comparison).message
      end

      # Resolve a directive into a Chart or an Unavailable. The reason is
      # decided in the documented order: comparison, invalid_arguments,
      # unknown_type, metrics_unavailable, unknown_target, data_missing.
      # @param directive [Directive] the parsed chart directive
      # @return [Chart, Unavailable]
      # @raise [ArgumentError] when directive is not a Directive
      def resolve(directive)
        raise ArgumentError, "directive must be a Directive" unless directive.is_a?(Directive)
        return unavailable(:comparison) if @comparison_mode
        return unavailable(:invalid_arguments) unless directive.valid_arguments?
        return unavailable(:unknown_type, type: directive.type) unless ChartType.key?(directive.type)
        return unavailable(:metrics_unavailable) unless usable_data?

        element = find_element(directive)
        return unavailable(:unknown_target, target: target_expression(directive)) unless element

        build_chart(directive, element)
      end

      # The targets addressable by a chart directive in this report's
      # metrics: every version, and every period whose stored period_name is
      # in the R-003 mapping. Repository periods are not targets.
      # @return [Array<Target>]
      def targets
        return [] unless usable_data?

        @data.filter_map do |element|
          next unless element.is_a?(Hash)

          if version_element?(element)
            Target.new(identifier: "version=#{element["version_id"]}", display_name: element["version_name"])
          elsif (key = PERIOD_NAME_TO_KEY[element["period_name"]])
            Target.new(identifier: "period=#{key}", display_name: period_display_name(key))
          end
        end
      end

      private

      def parse_metrics(json)
        JSON.parse(json)
      rescue JSON::ParserError
        nil
      end

      # A version element is addressable only with a positive Integer id and
      # a non-empty String name, so a corrupt stored value never reaches the
      # LLM guide as "version=-1 ()".
      def version_element?(element)
        element["version_id"].is_a?(Integer) && element["version_id"] >= 1 &&
          element["version_name"].is_a?(String) && !element["version_name"].empty?
      end

      def unavailable(reason, **interpolations)
        Unavailable.new(reason: reason, message: unavailable_message(reason, **interpolations))
      end

      def unavailable_message(reason, **interpolations)
        "#{l('ai_helper.health_report_chart.unavailable')}" \
          "#{l("ai_helper.health_report_chart.errors.#{reason}", **interpolations)}"
      end

      def usable_data?
        @data.is_a?(Array)
      end

      def find_element(directive)
        @data.each do |element|
          next unless element.is_a?(Hash)

          if directive.target_kind == :version
            return element if version_element?(element) && element["version_id"].to_s == directive.target_value
          elsif PERIOD_NAME_TO_KEY[element["period_name"]] == directive.target_value
            return element
          end
        end
        nil
      end

      def target_expression(directive)
        "#{directive.target_kind}=#{directive.target_value}"
      end

      def build_chart(directive, element)
        definition = ChartType[directive.type]
        values = extract_values(definition, element)
        return unavailable(:data_missing) if values.nil?

        items = build_items(definition, values)
        Chart.new(
          title: "#{l(definition[:title_key])} - #{target_display_name(directive, element)}",
          form: definition[:form],
          items: items,
          summary: definition[:form] == :tile ? tile_summary(values) : nil
        )
      end

      def target_display_name(directive, element)
        if directive.target_kind == :version
          element["version_name"]
        else
          period_display_name(directive.target_value)
        end
      end

      def period_display_name(key)
        l("ai_helper.health_report_chart.periods.#{key}")
      end

      # Extract the raw values for the type from one metrics element.
      # @return [Hash, Array, nil] {name => count} for :hash kinds, or the
      #   fixed [name, count] pairs; nil when the values are missing
      def extract_values(definition, element)
        metrics = element["metrics"].is_a?(Hash) ? element["metrics"] : {}
        issue_statistics = metrics["issue_statistics"].is_a?(Hash) ? metrics["issue_statistics"] : {}
        case definition[:kind]
        when :hash
          values = issue_statistics[definition[:key]]
          return nil unless values.is_a?(Hash) && values.values.all? { |count| count?(count) }

          values.dup
        when :open_closed
          open_issues = issue_statistics["open_issues"]
          closed_issues = issue_statistics["closed_issues"]
          return nil unless count?(open_issues) && count?(closed_issues)

          [ [ l(:label_open_issues), open_issues ], [ l(:label_closed_issues), closed_issues ] ]
        when :progress
          progress_metrics = metrics["progress_metrics"].is_a?(Hash) ? metrics["progress_metrics"] : {}
          distribution = progress_metrics["completion_distribution"]
          return nil unless distribution.is_a?(Hash)

          [ :not_started, :in_progress, :completed ].map do |key|
            value = distribution[key.to_s]
            return nil unless count?(value)

            [ l("ai_helper.health_report_chart.items.#{key}"), value ]
          end
        else
          # Unreachable while every ChartType kind is one of the kinds above;
          # the ChartType shape test keeps that true (CRF-010).
          raise ArgumentError, "unknown chart kind: #{definition[:kind].inspect}"
        end
      end

      # The number shown by an open/closed tile: closed of total and the
      # rounded completion rate. Called only for the :open_closed kind, whose
      # fixed values are [[open label, open], [closed label, closed]].
      def tile_summary(values)
        open_issues = values[0][1]
        closed_issues = values[1][1]
        total = open_issues + closed_issues
        rate = total.zero? ? 0 : (closed_issues * 100.0 / total).round
        l("ai_helper.health_report_chart.tile_summary", closed: closed_issues, total: total, rate: rate)
      end

      # A stored count is usable only as a non-negative Integer.
      def count?(value)
        value.is_a?(Integer) && value >= 0
      end

      def build_items(definition, values)
        pairs = definition[:item_mode] == :variable ? variable_pairs(values) : values
        pairs.each_with_index.map do |(name, count), index|
          rgb = definition[:kind] == :progress ? Palette::PROGRESS_COLORS.fetch(index) : Palette.color_at(index)
          Item.new(label: item_label(name, count), value: count, rgb: rgb)
        end
      end

      # Order a {name => count} mapping by count desc then name asc, and
      # group the remainder into "others" when there are more than 7 items
      # (R-005).
      def variable_pairs(values)
        sorted = values.sort_by { |name, count| [ -count, name ] }
        return sorted if sorted.length <= MAX_ITEMS

        top = sorted.first(MAX_ITEMS - 1)
        others_count = sorted.drop(MAX_ITEMS - 1).sum { |_, count| count }
        top + [ [ l("ai_helper.health_report_chart.items.other"), others_count ] ]
      end

      def item_label(name, count)
        l("ai_helper.health_report_chart.item_label", name: name.to_s, count: count)
      end
    end
  end
end
