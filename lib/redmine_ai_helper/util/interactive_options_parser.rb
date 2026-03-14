# frozen_string_literal: true

require "json"

module RedmineAiHelper
  module Util
    # Parses and strips interactive option blocks embedded in LLM responses.
    #
    # LLM responses may include a structured block at the end of the message:
    #   <!--AIHELPER_OPTIONS:{"choices":[{"label":"はい","value":"はい"},...]}-->
    #
    # This class provides methods to extract choices from that block and to
    # remove the block from the content before persisting it to the database.
    class InteractiveOptionsParser
      include RedmineAiHelper::Logger

      # Regex pattern matching the options block embedded in LLM responses.
      PATTERN = /<!--AIHELPER_OPTIONS:(.*?)-->/m

      # Return the content with the options block removed and whitespace stripped.
      #
      # @param content [String] LLM response full text
      # @return [String] body with the options block removed
      def self.strip(content)
        content.gsub(PATTERN, "").strip
      end

      # Extract the choices array from an options block in the LLM response.
      #
      # @param content [String] LLM response full text
      # @return [Array<Hash>, nil] array of {label:, value:} hashes, or nil if not present / invalid
      def self.extract_options(content)
        match = content.match(PATTERN)
        return nil unless match

        parsed = JSON.parse(match[1])
        choices = parsed["choices"]
        return nil if choices.nil? || choices.empty?

        result = choices.first(5).map do |c|
          { label: c["label"].to_s.strip, value: c["value"].to_s.strip }
        end.reject { |c| c[:label].empty? || c[:value].empty? }

        result.empty? ? nil : result
      rescue JSON::ParserError => e
        new.ai_helper_logger.error("InteractiveOptionsParser: JSON parse error: #{e.message}")
        nil
      end
    end
  end
end
