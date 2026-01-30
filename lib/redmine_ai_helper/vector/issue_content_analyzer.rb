# frozen_string_literal: true

require "json"

module RedmineAiHelper
  module Vector
    # Analyzes issue content using an LLM to extract summary and keywords
    # for improved vector search embedding.
    class IssueContentAnalyzer
      include RedmineAiHelper::Logger

      # JSON schema for the output structure
      JSON_SCHEMA = {
        type: "object",
        properties: {
          summary: {
            type: "string",
            description: "A concise summary including the problem, background, cause, and solution (if any). Maximum 200 characters."
          },
          keywords: {
            type: "array",
            items: { type: "string" },
            description: "Array of 5-10 important keywords (technical terms, error messages, feature names, component names)"
          }
        },
        required: ["summary", "keywords"],
        additionalProperties: false
      }.freeze

      # Initialize the analyzer with an optional LLM client.
      # @param llm [Object] Optional LLM client. If not provided, creates default from LlmProvider.
      def initialize(llm: nil)
        @llm = llm || RedmineAiHelper::LlmProvider.get_llm_provider.generate_client
      end

      # Analyze an issue and extract summary and keywords.
      # @param issue [Issue] The issue to analyze.
      # @return [Hash] A hash containing :summary (String) and :keywords (Array<String>).
      def analyze(issue)
        parser = create_parser
        prompt = build_prompt(issue, parser)
        response = call_llm(prompt)
        parse_response(response, parser)
      rescue StandardError => e
        ai_helper_logger.warn("Failed to analyze issue content: #{e.message}")
        empty_result
      end

      private

      # Create a StructuredOutputParser from the JSON schema.
      # @return [Langchain::OutputParsers::StructuredOutputParser]
      def create_parser
        Langchain::OutputParsers::StructuredOutputParser.from_json_schema(JSON_SCHEMA)
      end

      # Build the prompt for the LLM from the issue data.
      # @param issue [Issue] The issue to build a prompt for.
      # @param parser [Langchain::OutputParsers::StructuredOutputParser] The output parser.
      # @return [String] The formatted prompt string.
      def build_prompt(issue, parser)
        issue_data = {
          subject: issue.subject,
          description: issue.description || "",
          journals: issue.journals.map { |j| j.notes.to_s }.reject(&:blank?)
        }

        template = RedmineAiHelper::Util::PromptLoader.load_template("vector/issue_content_analysis")
        template.format(
          issue: issue_data.to_json,
          format_instructions: parser.get_format_instructions
        )
      end

      # Call the LLM with the given prompt.
      # @param prompt [String] The prompt to send to the LLM.
      # @return [String] The text response from the LLM.
      def call_llm(prompt)
        messages = [{ role: "user", content: prompt }]
        response = @llm.chat(messages: messages)
        response.chat_completion
      end

      # Parse the LLM response using StructuredOutputParser with OutputFixingParser.
      # @param response [String] The raw response text from the LLM.
      # @param parser [Langchain::OutputParsers::StructuredOutputParser] The output parser.
      # @return [Hash] A hash containing :summary (String) and :keywords (Array<String>).
      def parse_response(response, parser)
        return empty_result if response.nil? || response.strip.empty?

        # Use OutputFixingParser to handle minor formatting issues in LLM response
        fix_parser = Langchain::OutputParsers::OutputFixingParser.from_llm(
          llm: @llm,
          parser: parser
        )

        result = fix_parser.parse(response)

        {
          summary: result["summary"].to_s,
          keywords: result["keywords"].is_a?(Array) ? result["keywords"] : []
        }
      rescue StandardError => e
        ai_helper_logger.warn("Failed to parse LLM response: #{e.message}")
        empty_result
      end

      # Return an empty result structure.
      # @return [Hash] A hash with empty summary and keywords.
      def empty_result
        { summary: "", keywords: [] }
      end
    end
  end
end
