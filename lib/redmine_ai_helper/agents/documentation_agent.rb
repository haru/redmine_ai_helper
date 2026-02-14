require 'set'

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
      def check_typos(text:, context_type: 'general', **options)
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
                enum: ["high", "medium", "low"],
                description: "Confidence level"
              }
            },
            required: ["original", "corrected", "position", "length", "reason", "confidence"],
            additionalProperties: false
          },
          minItems: 0,
          description: "Array of typo correction suggestions"
        }

        format_instructions = RedmineAiHelper::Util::StructuredOutputHelper.get_format_instructions(json_schema)

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
            "role" => "user",
            "content" => formatted_prompt
          }
        ]

        response = chat(messages)

        suggestions = RedmineAiHelper::Util::StructuredOutputHelper.parse(
          response: response,
          json_schema: json_schema,
          chat_method: method(:chat),
          messages: messages,
        )
        
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
        
        validated = []
        used_positions = Set.new  # Track used positions to avoid duplicates
        
        suggestions.each do |suggestion|
          next unless suggestion.is_a?(Hash)
          next unless suggestion['original'] && suggestion['corrected'] && suggestion['position']
          
          # Validate and fix position
          position = suggestion['position'].to_i
          original = suggestion['original'].to_s
          corrected = suggestion['corrected'].to_s
          
          # Skip if original and corrected are the same
          if original == corrected
            ai_helper_logger.warn "Skipping suggestion where original and corrected are identical: '#{original}'"
            next
          end
          
          # Skip if original or corrected are empty or only whitespace
          if original.strip.empty? || corrected.strip.empty?
            ai_helper_logger.warn "Skipping suggestion with empty original or corrected text: original='#{original}', corrected='#{corrected}'"
            next
          end
          
          # Check if position is valid
          if position < 0 || position >= original_text.length
            ai_helper_logger.warn "Invalid position #{position} for suggestion: #{original}"
            # Try to find all possible positions for this text
            all_positions = []
            start_pos = 0
            while (found_pos = original_text.index(original, start_pos))
              all_positions << found_pos unless used_positions.include?(found_pos)
              start_pos = found_pos + 1
            end
            
            if all_positions.any?
              position = all_positions.first
              ai_helper_logger.info "Found correct position #{position} for: #{original} (available positions: #{all_positions})"
            else
              ai_helper_logger.warn "Could not find unused position for: #{original}, skipping"
              next
            end
          end
          
          # Validate and fix length - always use the actual length of the original text
          actual_length = original.length
          ai_provided_length = suggestion['length'].to_i
          
          if ai_provided_length != actual_length
            ai_helper_logger.warn "AI provided incorrect length #{ai_provided_length} for '#{original}' (actual: #{actual_length})"
          end
          
          # Verify text at position matches
          text_at_position = original_text[position, actual_length]
          if text_at_position != original
            ai_helper_logger.warn "Text mismatch at position #{position}: expected '#{original}', found '#{text_at_position}'"
            # Try to find all unused positions for this text
            all_positions = []
            start_pos = 0
            while (found_pos = original_text.index(original, start_pos))
              all_positions << found_pos unless used_positions.include?(found_pos)
              start_pos = found_pos + 1
            end
            
            if all_positions.any?
              position = all_positions.first
              ai_helper_logger.info "Corrected position to #{position} for: #{original} (available positions: #{all_positions})"
              # Verify the corrected position
              text_at_position = original_text[position, actual_length]
              if text_at_position != original
                ai_helper_logger.warn "Even corrected position #{position} doesn't match for: #{original}, skipping"
                next
              end
            else
              ai_helper_logger.warn "Could not find unused position for text '#{original}' in original text, skipping"
              next
            end
          end
          
          # Skip if this position is already used (prevents duplicates)
          if used_positions.include?(position)
            ai_helper_logger.warn "Position #{position} already used for another suggestion, skipping duplicate for: #{original}"
            next
          end
          
          # Mark this position as used
          used_positions.add(position)
          
          validated << {
            'original' => original,
            'corrected' => corrected,
            'position' => position,
            'length' => actual_length,  # Always use actual length
            'reason' => suggestion['reason'].to_s,
            'confidence' => suggestion['confidence'].to_s
          }
        end
        
        ai_helper_logger.info "Validated #{validated.length} out of #{suggestions.length} suggestions"
        validated
      end
    end
  end
end