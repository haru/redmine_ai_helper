# frozen_string_literal: true

module RedmineAiHelper
  module LlmClient
    # System prompt split into a part that stays the same between calls
    # (+fixed+, the cacheable prefix) and a part that changes per call or per
    # user (+variable+, e.g. the current time). Providers without explicit
    # prompt caching receive the two parts joined into a single string.
    #
    # @!attribute [r] fixed
    #   @return [String] the part of the system prompt that does not change
    # @!attribute [r] variable
    #   @return [String] the part that changes per call; may be empty
    Instructions = Data.define(:fixed, :variable) do
      # The prompt as a single string, for providers that do not cache explicitly.
      # @return [String]
      def to_s
        variable.to_s.empty? ? fixed : "#{fixed}\n\n#{variable}"
      end
    end
  end
end
