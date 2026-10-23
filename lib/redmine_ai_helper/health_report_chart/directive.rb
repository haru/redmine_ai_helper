# frozen_string_literal: true

module RedmineAiHelper
  module HealthReportChart
    # A single chart directive line ({{ai_helper_chart(...)}}) parsed from a
    # report body. Holds the chart type and its target (a version or a
    # period) without interpreting the metrics. A line whose arguments do
    # not follow the documented syntax is still kept as a Directive with
    # target_kind: nil, so renderers can show a "cannot draw" reason instead
    # of the raw line.
    class Directive
      # The allowed values of target_kind.
      VALID_TARGET_KINDS = [ nil, :version, :period ].freeze

      attr_reader :type, :target_kind, :target_value, :source

      # @param type [String] the chart type key as written in the directive
      # @param target_kind [Symbol, nil] :version, :period, or nil when the
      #   argument syntax is malformed
      # @param target_value [String, nil] the version id (digits) or period
      #   key; must be nil exactly when target_kind is nil
      # @param source [String] the original line without surrounding whitespace
      # @raise [ArgumentError] when an attribute violates the documented invariants
      def initialize(type:, target_kind:, target_value:, source:)
        raise ArgumentError, "type must be a String" unless type.is_a?(String)
        raise ArgumentError, "source must be a String" unless source.is_a?(String)
        unless VALID_TARGET_KINDS.include?(target_kind)
          raise ArgumentError, "target_kind must be nil, :version or :period"
        end
        if target_kind.nil?
          raise ArgumentError, "target_value must be nil when target_kind is nil" unless target_value.nil?
        else
          unless target_value.is_a?(String) && !target_value.empty?
            raise ArgumentError, "target_value must be a non-empty String when target_kind is set"
          end
          if target_kind == :version && !target_value.match?(/\A\d+\z/)
            raise ArgumentError, "a version target_value must be all digits"
          end
        end

        @type = type
        @target_kind = target_kind
        @target_value = target_value
        @source = source
      end

      # True when the directive's arguments follow the documented syntax.
      # @return [Boolean]
      def valid_arguments?
        !target_kind.nil?
      end
    end
  end
end
