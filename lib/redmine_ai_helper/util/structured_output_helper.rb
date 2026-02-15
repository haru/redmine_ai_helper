# frozen_string_literal: true

require "json"

module RedmineAiHelper
  module Util
    # Provides format instructions generation and JSON parsing with retry.
    class StructuredOutputHelper
      class << self
        # Generate format instructions from a JSON schema.
        # Generates format instructions to embed in a prompt.
        # @param json_schema [Hash] The JSON schema
        # @return [String] Format instructions to embed in a prompt
        def get_format_instructions(json_schema)
          schema_json = JSON.generate(json_schema)
          <<~INSTRUCTIONS
            You must format your output as a JSON value that adheres to a given "JSON Schema" instance.

            "JSON Schema" is a declarative language that allows you to annotate and validate JSON documents.

            For example, the example "JSON Schema" instance {"properties": {"foo": {"description": "a list of test words", "type": "array", "items": {"type": "string"}}}, "required": ["foo"]}}
            would match an object with one required property, "foo". The "type" property specifies "foo" must be an "array", and the "description" property semantically describes it as "a list of test words". The items within "foo" must be strings.
            Thus, the object {"foo": ["bar", "baz"]} is a well-formatted instance of this example "JSON Schema". The object {"properties": {"foo": ["bar", "baz"]}}} is not well-formatted.

            Your output will be parsed and type-checked according to the provided schema instance, so make sure all fields in your output match the schema exactly and there are no trailing commas!

            Here is the JSON Schema instance your output must adhere to. Include the enclosing markdown codeblock:
            ```json
            #{schema_json}
            ```
          INSTRUCTIONS
        end

        # Parse structured JSON output from an LLM response.
        # Tries direct parsing first, then retries with the LLM if a chat_method is provided.
        # @param response [String] The raw LLM response
        # @param json_schema [Hash] The JSON schema (used for retry instructions)
        # @param chat_method [Proc, nil] A method to call for retry (receives messages array, returns string)
        # @param messages [Array<Hash>, nil] Original messages for retry context
        # @return [Hash, Array] The parsed JSON object
        # @raise [JSON::ParserError] If parsing fails and no retry is possible
        def parse(response:, json_schema:, chat_method: nil, messages: nil)
          parse_json_from_response(response)
        rescue JSON::ParserError => e
          raise e unless chat_method && messages

          retry_with_llm(
            response: response,
            json_schema: json_schema,
            chat_method: chat_method,
            messages: messages,
          )
        end

        private

        # Extract and parse JSON from a response string.
        # Handles JSON wrapped in ```json ... ``` code blocks.
        # @param response [String] The raw response
        # @return [Hash, Array] Parsed JSON
        # @raise [JSON::ParserError] If no valid JSON is found
        def parse_json_from_response(response)
          return JSON.parse(response.strip) if response.strip.start_with?("{", "[")

          # Try to extract from ```json ... ``` or ``` ... ``` blocks
          json_match = response.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m)
          if json_match
            return JSON.parse(json_match[1].strip)
          end

          # Fall back to direct parse
          JSON.parse(response.strip)
        end

        # Retry parsing by sending the failed response back to the LLM with fix instructions.
        # @param response [String] The original failed response
        # @param json_schema [Hash] The JSON schema
        # @param chat_method [Proc] The chat method to use for retry
        # @param messages [Array<Hash>] The original messages
        # @return [Hash, Array] Parsed JSON from retry
        # @raise [JSON::ParserError] If retry also fails
        def retry_with_llm(response:, json_schema:, chat_method:, messages:)
          fix_prompt = <<~PROMPT
            The following response was supposed to be a valid JSON object matching the schema below, but it could not be parsed.

            Response:
            #{response}

            Expected JSON Schema:
            ```json
            #{JSON.pretty_generate(json_schema)}
            ```

            Please output ONLY a valid JSON object that matches the schema. No additional text.
          PROMPT

          new_messages = messages.dup
          new_messages << { role: "user", content: fix_prompt }
          fixed_response = chat_method.call(new_messages)
          parse_json_from_response(fixed_response)
        end
      end
    end
  end
end
