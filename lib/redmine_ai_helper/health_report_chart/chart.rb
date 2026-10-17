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
    # - kind: :hash reads a {name => count} mapping at
    #   metrics.issue_statistics.<key>; :open_closed reads open_issues /
    #   closed_issues; :progress reads
    #   progress_metrics.completion_distribution.{not_started,in_progress,completed}
    # - item_mode: :variable orders items by count (R-005) and groups the
    #   remainder into "others"; :fixed keeps the documented fixed order and
    #   never groups.
    ChartType = {
      "status" => { title_key: "ai_helper.health_report_chart.types.status", form: :doughnut, kind: :hash, key: "by_status", item_mode: :variable },
      "tracker" => { title_key: "ai_helper.health_report_chart.types.tracker", form: :doughnut, kind: :hash, key: "by_tracker", item_mode: :variable },
      "priority" => { title_key: "ai_helper.health_report_chart.types.priority", form: :doughnut, kind: :hash, key: "by_priority", item_mode: :variable },
      "assignee" => { title_key: "ai_helper.health_report_chart.types.assignee", form: :bar, kind: :hash, key: "by_assigned_to", item_mode: :variable },
      "open_closed" => { title_key: "ai_helper.health_report_chart.types.open_closed", form: :doughnut, kind: :open_closed, item_mode: :fixed },
      "progress" => { title_key: "ai_helper.health_report_chart.types.progress", form: :doughnut, kind: :progress, item_mode: :fixed }
    }.freeze

    # A drawable chart: the title, the form and the ordered items. The three
    # renderers (screen, PDF, SVG) take only this object as input (FR-019).
    class Chart
      attr_reader :title, :form, :items

      # @param title [String] non-empty display title
      # @param form [Symbol] :doughnut or :bar
      # @param items [Array<Item>] at most 7 items in display order
      # @raise [ArgumentError] when an attribute violates the documented invariants
      def initialize(title:, form:, items:)
        raise ArgumentError, "title must be a non-empty String" unless title.is_a?(String) && !title.empty?
        raise ArgumentError, "form must be :doughnut or :bar" unless [ :doughnut, :bar ].include?(form)
        raise ArgumentError, "items must be an Array of at most 7 items" unless items.is_a?(Array) && items.length <= 7
        items.each { |item| raise ArgumentError, "items must be Item objects" unless item.is_a?(Item) }

        @title = title
        @form = form
        @items = items
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
        unless rgb.is_a?(Array) && rgb.length == 3 && rgb.all?(Integer)
          raise ArgumentError, "rgb must be [r, g, b] integers"
        end

        @label = label
        @value = value
        @rgb = rgb
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
      attr_reader :reason, :message

      # @param reason [Symbol] one of the reasons in data-model.md's table
      # @param message [String] the localized "cannot draw" message
      def initialize(reason:, message:)
        @reason = reason
        @message = message
      end
    end
  end
end
