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

      # Initialize the analyzer with an optional LLM provider.
      # @param llm_provider [Object] Optional LLM provider. If not provided, creates default from LlmProvider.
      def initialize(llm_provider: nil)
        @llm_provider = llm_provider || RedmineAiHelper::LlmProvider.get_llm_provider
      end

      # Analyze an issue and extract summary and keywords.
      # @param issue [Issue] The issue to analyze.
      # @return [Hash] A hash containing :summary (String) and :keywords (Array<String>).
      def analyze(issue)
        format_instructions = RedmineAiHelper::Util::StructuredOutputHelper.get_format_instructions(JSON_SCHEMA)
        prompt = build_prompt(issue, format_instructions)
        messages = [{ role: "user", content: prompt }]
        response = call_llm(messages)
        parse_response(response, messages)
      rescue StandardError => e
        ai_helper_logger.warn("Failed to analyze issue content: #{e.message}")
        empty_result
      end

      private

      # Build the prompt for the LLM from the issue data.
      # @param issue [Issue] The issue to build a prompt for.
      # @param format_instructions [String] The format instructions for the output.
      # @return [String] The formatted prompt string.
      def build_prompt(issue, format_instructions)
        issue_data = {
          subject: issue.subject,
          description: issue.description || "",
          journals: issue.journals.map { |j| j.notes.to_s }.reject(&:blank?)
        }

        template = RedmineAiHelper::Util::PromptLoader.load_template("vector/issue_content_analysis")
        template.format(
          issue: issue_data.to_json,
          format_instructions: format_instructions
        )
      end

      # Call the LLM with the given messages.
      # @param messages [Array<Hash>] The messages to send to the LLM.
      # @return [String] The text response from the LLM.
      def call_llm(messages)
        chat_instance = @llm_provider.create_chat

        # Add message history (all except the last message)
        messages[0..-2].each do |msg|
          chat_instance.add_message(role: msg[:role].to_sym, content: msg[:content])
        end

        # Ask with the last message
        last_message = messages.last
        response = chat_instance.ask(last_message[:content])
        response.content
      end

      # Parse the LLM response using StructuredOutputHelper.
      # @param response [String] The raw response text from the LLM.
      # @param messages [Array<Hash>] The original messages for retry context.
      # @return [Hash] A hash containing :summary (String) and :keywords (Array<String>).
      def parse_response(response, messages)
        return empty_result if response.nil? || response.strip.empty?

        result = RedmineAiHelper::Util::StructuredOutputHelper.parse(
          response: response,
          json_schema: JSON_SCHEMA,
          chat_method: method(:call_llm),
          messages: messages,
        )

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
