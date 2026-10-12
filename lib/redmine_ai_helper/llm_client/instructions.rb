# frozen_string_literal: true

module RedmineAiHelper
  module LlmClient
    # System prompt split into a part that stays the same between calls
    # (+fixed+, the cacheable prefix) and a part that changes per call or per
    # user (+variable+, e.g. the current time). Providers that do not apply
    # explicit prompt caching (including Anthropic with caching disabled)
    # receive the two parts joined into a single string.
    #
    # @!attribute [r] fixed
    #   @return [String] the part of the system prompt that does not change; never empty
    # @!attribute [r] variable
    #   @return [String] the part that changes per call; may be empty
    Instructions = Data.define(:fixed, :variable) do
      # Converts a system prompt given to a provider into Instructions.
      # A plain String becomes the fixed part with an empty variable part.
      # @param value [String, Instructions, nil] system prompt
      # @return [Instructions, nil] nil when +value+ is nil
      # @raise [ArgumentError] when +value+ is of any other type
      def self.coerce(value)
        case value
        when nil, self then value
        when String then new(fixed: value)
        else raise ArgumentError, "Unsupported instructions type: #{value.class}"
        end
      end

      # @param fixed [String] the part that does not change; must not be empty
      # @param variable [String] the part that changes per call
      # @raise [ArgumentError] when +fixed+ is not a non-empty String or
      #   +variable+ is not a String
      def initialize(fixed:, variable: "")
        raise ArgumentError, "fixed instructions must be a non-empty String" unless fixed.is_a?(String) && !fixed.empty?
        raise ArgumentError, "variable instructions must be a String" unless variable.is_a?(String)

        super
      end

      # Whether the variable part has any content.
      # @return [Boolean]
      def variable?
        !variable.empty?
      end

      # The prompt as a single string, for providers that do not cache explicitly.
      # @return [String]
      def to_s
        variable? ? "#{fixed}\n\n#{variable}" : fixed
      end
    end
  end
end
