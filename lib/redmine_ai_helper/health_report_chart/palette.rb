# frozen_string_literal: true

module RedmineAiHelper
  module HealthReportChart
    # The 6-color palette of Redmine's issue report charts (FR-019a). The
    # same assignment order is shared by the screen, PDF and SVG renderers.
    module Palette
      # The RGB colors assigned to items in display order.
      COLORS = [
        [ 255, 99, 132 ], [ 54, 162, 235 ], [ 255, 206, 86 ],
        [ 75, 192, 192 ], [ 153, 102, 255 ], [ 255, 159, 64 ]
      ].freeze
      # The opacity used to fill slices and bars (borders are opaque).
      FILL_ALPHA = 0.2

      class << self
        # The color for the item at `index`; wraps around to the first color
        # from the 7th item on.
        # @param index [Integer] the item's zero-based display position
        # @return [Array<Integer>] [r, g, b]
        def color_at(index)
          COLORS[index % COLORS.length]
        end
      end
    end
  end
end
