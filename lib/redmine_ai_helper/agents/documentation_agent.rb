module RedmineAiHelper
  module Agents
    class DocumentationAgent < BaseAgent
      def initialize(options = {})
        super
        @project = options[:project]
      end

      def backstory
        load_prompt("documentation_agent/backstory")
      end

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

        parser = Langchain::OutputParsers::StructuredOutputParser.from_json_schema(json_schema)

        prompt_template = load_prompt("documentation_agent/typo_check")
        
        formatted_prompt = prompt_template.format(
          text: text,
          context_type: context_type,
          max_suggestions: options[:max_suggestions] || 10,
          format_instructions: parser.get_format_instructions
        )

        # Create proper message array for BaseAgent#chat
        messages = [
          {
            "role" => "user",
            "content" => formatted_prompt
          }
        ]

        response = chat(messages, output_parser: parser)

        fix_parser = Langchain::OutputParsers::OutputFixingParser.from_llm(
          llm: client,
          parser: parser
        )
        
        suggestions = fix_parser.parse(response)
        
        # Validate and fix suggestions data
        validated_suggestions = validate_and_fix_suggestions(suggestions, text)
        
        validated_suggestions
      end

      def available_tools
        []
      end

      private

      def validate_and_fix_suggestions(suggestions, original_text)
        return [] unless suggestions.is_a?(Array)
        
        validated = []
        
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
            # Try to find the correct position
            correct_position = original_text.index(original)
            if correct_position
              position = correct_position
              ai_helper_logger.info "Found correct position #{correct_position} for: #{original}"
            else
              ai_helper_logger.warn "Could not find correct position for: #{original}, skipping"
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
            # Try to find correct position
            correct_position = original_text.index(original)
            if correct_position
              position = correct_position
              ai_helper_logger.info "Corrected position to #{correct_position} for: #{original}"
            else
              ai_helper_logger.warn "Could not find text '#{original}' in original text, skipping"
              next
            end
          end
          
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