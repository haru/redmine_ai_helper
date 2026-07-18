require "set"

module RedmineAiHelper
  module Agents
    # Agent for documentation-related tasks like typo checking
    class DocumentationAgent < BaseAgent
      def initialize(options = {})
        super
        @project = options[:project]
      end

      # Get the agent's backstory
      # @return [String] The backstory prompt
      def backstory
        load_prompt("documentation_agent/backstory")
      end

      # Check text for typos and return suggestions
      # @param text [String] The text to check
      # @param context_type [String] The context type (general, code, etc.)
      # @param options [Hash] Additional options
      # @return [Array<Hash>] Array of typo correction suggestions
      def check_typos(text:, context_type: "general", **options)
        json_schema = {
          type: "array",
          items: {
            type: "object",
            properties: {
              original: {
                type: "string",
                description: "Original incorrect text"
              },
              corrected: {
                type: "string",
                description: "Corrected text"
              },
              position: {
                type: "number",
                description: "Character position in original text"
              },
              length: {
                type: "number",
                description: "Length of text to replace"
              },
              reason: {
                type: "string",
                description: "Brief explanation of the correction"
              },
              confidence: {
                type: "string",
                enum: [ "high", "medium", "low" ],
                description: "Confidence level"
              }
            },
            required: [ "original", "corrected", "position", "length", "reason", "confidence" ],
            additionalProperties: false
          },
          minItems: 0,
          description: "Array of typo correction suggestions"
        }

        format_instructions = format_instructions_for(json_schema)

        prompt_template = load_prompt("documentation_agent/typo_check")

        formatted_prompt = prompt_template.format(
          text: text,
          context_type: context_type,
          max_suggestions: options[:max_suggestions] || 10,
          format_instructions: format_instructions
        )

        # Create proper message array for BaseAgent#chat
        messages = [
          {
            role: "user",
            content: formatted_prompt
          }
        ]

        suggestions = structured_chat(messages, json_schema: json_schema)

        # Validate and fix suggestions data
        validated_suggestions = validate_and_fix_suggestions(suggestions, text)

        validated_suggestions
      end

      # Get available tools for this agent
      # @return [Array] Empty array (no tools needed)
      def available_tools
        []
      end

      private

      def validate_and_fix_suggestions(suggestions, original_text)
        return [] unless suggestions.is_a?(Array)

        used_positions = Set.new
        validated = []

        suggestions.each do |suggestion|
          result = build_validated_suggestion(suggestion, original_text, used_positions)
          next unless result

          used_positions.add(result["position"])
          validated << result
        end

        ai_helper_logger.info "Validated #{validated.length} out of #{suggestions.length} suggestions"
        validated
      end

      def build_validated_suggestion(suggestion, original_text, used_positions)
        return nil unless suggestion.is_a?(Hash)
        return nil unless suggestion["original"] && suggestion["corrected"] && suggestion["position"]

        original = suggestion["original"].to_s
        corrected = suggestion["corrected"].to_s
        return nil if original == corrected || original.strip.empty? || corrected.strip.empty?

        position = resolve_suggestion_position(suggestion["position"].to_i, original, original_text, used_positions)
        return nil unless position

        actual_length = original.length
        ai_provided_length = suggestion["length"].to_i
        ai_helper_logger.warn "AI provided incorrect length #{ai_provided_length} for '#{original}' (actual: #{actual_length})" if ai_provided_length != actual_length

        if used_positions.include?(position)
          ai_helper_logger.warn "Position #{position} already used for another suggestion, skipping duplicate for: #{original}"
          return nil
        end

        { "original" => original, "corrected" => corrected, "position" => position, "length" => actual_length, "reason" => suggestion["reason"].to_s, "confidence" => suggestion["confidence"].to_s }
      end

      def resolve_suggestion_position(position, original, original_text, used_positions)
        actual_length = original.length
        if position < 0 || position >= original_text.length
          ai_helper_logger.warn "Invalid position #{position} for suggestion: #{original}"
          found = find_unused_position(original_text, original, used_positions)
          return log_and_skip("Could not find unused position for: #{original}") unless found

          ai_helper_logger.info "Found correct position #{found} for: #{original}"
          return found
        end

        return position if original_text[position, actual_length] == original

        ai_helper_logger.warn "Text mismatch at position #{position}: expected '#{original}', found '#{original_text[position, actual_length]}'"
        found = find_unused_position(original_text, original, used_positions)
        return log_and_skip("Could not find unused position for text '#{original}' in original text") unless found

        ai_helper_logger.info "Corrected position to #{found} for: #{original}"
        return log_and_skip("Even corrected position #{found} doesn't match for: #{original}") if original_text[found, actual_length] != original

        found
      end

      def log_and_skip(message)
        ai_helper_logger.warn "#{message}, skipping"
        nil
      end

      def find_unused_position(original_text, original, used_positions)
        start_pos = 0
        while (found_pos = original_text.index(original, start_pos))
          return found_pos unless used_positions.include?(found_pos)

          start_pos = found_pos + 1
        end
        nil
      end
    end
  end
end
