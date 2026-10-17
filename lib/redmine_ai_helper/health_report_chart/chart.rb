# frozen_string_literal: true

require "redmine_ai_helper/health_report_chart/palette"

module RedmineAiHelper
  # Charts embedded in health reports through one-line chart directives.
  module HealthReportChart
    # Definitions of the chart types that can be requested by a chart
    # directive (FR-003). Each entry tells where the values come from in the
    # stored metrics, which chart form draws them, and how the items are
    # ordered. Keys and values are plain strings/symbols so the hash works
    # on parsed JSON data directly.
    #
    # - form: :bar (count-ordered horizontal bars), :stacked (one stacked
    #   horizontal bar of ordered stages) or :tile (a number tile, no chart)
    #   (R-004)
    # - kind: :hash reads a {name => count} mapping at
    #   metrics.issue_statistics.<key>; :open_closed reads open_issues /
    #   closed_issues; :progress reads
    #   progress_metrics.completion_distribution.{not_started,in_progress,completed}
    # - item_mode: :variable orders items by count (R-005) and groups the
    #   remainder into "others"; :fixed keeps the documented fixed order and
    #   never groups.
    ChartType = {
      "status" => { title_key: "ai_helper.health_report_chart.types.status", form: :bar, kind: :hash, key: "by_status", item_mode: :variable }.freeze,
      "tracker" => { title_key: "ai_helper.health_report_chart.types.tracker", form: :bar, kind: :hash, key: "by_tracker", item_mode: :variable }.freeze,
      "priority" => { title_key: "ai_helper.health_report_chart.types.priority", form: :bar, kind: :hash, key: "by_priority", item_mode: :variable }.freeze,
      "assignee" => { title_key: "ai_helper.health_report_chart.types.assignee", form: :bar, kind: :hash, key: "by_assigned_to", item_mode: :variable }.freeze,
      "open_closed" => { title_key: "ai_helper.health_report_chart.types.open_closed", form: :tile, kind: :open_closed, item_mode: :fixed }.freeze,
      "progress" => { title_key: "ai_helper.health_report_chart.types.progress", form: :stacked, kind: :progress, item_mode: :fixed }.freeze
    }.freeze

    # A drawable chart: the title, the form and the ordered items. The three
    # renderers (screen, PDF, SVG) take only this object as input (FR-019).
    class Chart
      # The maximum number of items: the top 6 plus "others" (R-005).
      MAX_ITEMS = 7

      # The drawing forms (R-004).
      FORMS = %i[bar stacked tile].freeze

      attr_reader :title, :form, :items, :summary

      # @param title [String] non-empty display title
      # @param form [Symbol] one of FORMS
      # @param items [Array<Item>] at most 7 items in display order
      # @param summary [String, nil] the number shown by a :tile chart; must be
      #   a non-empty String for :tile and nil for the other forms
      # @raise [ArgumentError] when an attribute violates the documented invariants
      def initialize(title:, form:, items:, summary: nil)
        raise ArgumentError, "title must be a non-empty String" unless title.is_a?(String) && !title.empty?
        raise ArgumentError, "form must be one of #{FORMS.inspect}" unless FORMS.include?(form)
        if form == :tile
          raise ArgumentError, "a :tile chart needs a non-empty String summary" unless summary.is_a?(String) && !summary.empty?
        elsif !summary.nil?
          raise ArgumentError, "only a :tile chart has a summary"
        end
        raise ArgumentError, "items must be an Array of at most #{MAX_ITEMS} items" unless items.is_a?(Array) && items.length <= MAX_ITEMS
        items.each { |item| raise ArgumentError, "items must be Item objects" unless item.is_a?(Item) }

        @title = title.dup.freeze
        @form = form
        @summary = summary&.dup&.freeze
        @items = items.dup.freeze
      end

      # True when the chart has nothing to draw (no items, or all values 0).
      # @return [Boolean]
      def no_data?
        items.sum(&:value).zero?
      end
    end

    # One slice/bar of a chart. The label is fully formatted ("Name (3)");
    # the colors are derived from the palette rgb assigned by the Resolver.
    class Item
      attr_reader :label, :value, :rgb

      # @param label [String] formatted item label including the count
      # @param value [Integer] the item's count (0 or more)
      # @param rgb [Array<Integer>] [r, g, b] palette color
      # @raise [ArgumentError] when an attribute violates the documented invariants
      def initialize(label:, value:, rgb:)
        raise ArgumentError, "label must be a String" unless label.is_a?(String)
        unless value.is_a?(Integer) && value >= 0
          raise ArgumentError, "value must be an Integer of 0 or more"
        end
        unless rgb.is_a?(Array) && rgb.length == 3 && rgb.all? { |c| c.is_a?(Integer) && c.between?(0, 255) }
          raise ArgumentError, "rgb must be [r, g, b] integers in 0..255"
        end

        @label = label
        @value = value
        @rgb = rgb.dup.freeze
      end

      # The CSS fill color with the shared fill alpha.
      # @return [String] e.g. "rgba(255, 99, 132, 0.2)"
      def fill_color
        format("rgba(%d, %d, %d, %s)", *rgb, Palette::FILL_ALPHA)
      end

      # The CSS border color (opaque).
      # @return [String] e.g. "rgb(255, 99, 132)"
      def border_color
        format("rgb(%d, %d, %d)", *rgb)
      end
    end

    # A chart directive that cannot be drawn, with the localized reason.
    class Unavailable
      # The documented reasons (data-model.md), in the order Resolver checks them.
      REASONS = %i[comparison invalid_arguments unknown_type metrics_unavailable unknown_target data_missing].freeze

      attr_reader :reason, :message

      # @param reason [Symbol] one of REASONS
      # @param message [String] the localized "cannot draw" message
      # @raise [ArgumentError] when the reason is undocumented or the message
      #   is not a non-empty String
      def initialize(reason:, message:)
        raise ArgumentError, "reason must be one of #{REASONS.inspect}" unless REASONS.include?(reason)
        raise ArgumentError, "message must be a non-empty String" unless message.is_a?(String) && !message.empty?

        @reason = reason
        @message = message
      end
    end
  end
end
