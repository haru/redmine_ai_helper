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
        
        fix_parser.parse(response)
      end

      def available_tools
        []
      end
    end
  end
end