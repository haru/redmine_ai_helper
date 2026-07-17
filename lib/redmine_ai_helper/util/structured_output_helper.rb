# frozen_string_literal: true

require "json"
require "redmine_ai_helper/logger"

module RedmineAiHelper
  module Util
    # Provides format instructions generation and JSON parsing with schema
    # conformance, validation, and a single LLM regeneration retry.
    class StructuredOutputHelper
      extend RedmineAiHelper::Logger::ClassMethods

      # Error raised when an LLM response cannot be conformed to the requested
      # JSON schema even after a single regeneration attempt.
      class SchemaViolationError < StandardError
        # @return [Array<String>] The list of detected schema violations.
        attr_reader :violations

        # @param message [String] Human-readable summary of the violation.
        # @param violations [Array<String>] The detected violations.
        def initialize(message, violations)
          super(message)
          @violations = violations
        end
      end

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

        # Parse structured JSON output from an LLM response and ensure it
        # conforms to the given schema.
        #
        # String responses are JSON-parsed (with a single parse-fix retry when a
        # chat_method is available). Hash/Array responses (e.g. from native
        # structured output) are used directly. The parsed value is then
        # conformed (wrapped/trimmed) and validated against the schema. On
        # validation violations, a single regeneration is requested via
        # chat_method when available; otherwise SchemaViolationError is raised.
        #
        # @param response [String, Hash, Array] The raw LLM response or a
        #   pre-parsed Hash/Array.
        # @param json_schema [Hash] The JSON schema.
        # @param chat_method [Proc, nil] A method to call for retries (receives
        #   the messages array, returns a String response).
        # @param messages [Array<Hash>, nil] Original messages for retry context.
        # @return [Hash, Array] The conformed, schema-valid value.
        # @raise [JSON::ParserError] If parsing fails and no/limited retry helps.
        # @raise [SchemaViolationError] If the response cannot be conformed.
        def parse(response:, json_schema:, chat_method: nil, messages: nil)
          data = parsed_data_from(
            response,
            json_schema: json_schema,
            chat_method: chat_method,
            messages: messages
          )
          conform_and_validate(
            data,
            json_schema: json_schema,
            chat_method: chat_method,
            messages: messages
          )
        end

        # Conform a parsed value to a JSON schema without mutating the input.
        #
        # Currently performs two deterministic transforms:
        #   * wraps a bare Array into the single array-type property when the
        #     schema is an object with exactly one array property;
        #   * recursively removes keys not declared in object `properties`
        #     (descending into `properties` and `items`).
        #
        # Schema keys may be symbols or strings (normalized internally).
        # @param data [Object] The parsed value.
        # @param json_schema [Hash] The JSON schema.
        # @return [Object] A new, conformed value.
        def conform_to_schema(data, json_schema)
          schema = stringify_keys(json_schema)
          conform_value(stringify_keys(data), schema)
        end

        # Validate a value against a JSON schema.
        #
        # Only `required` key presence and `type` mismatches are checked
        # (recursively). No value coercion is performed. `format` and `enum`
        # are intentionally not validated.
        # @param data [Object] The value to validate.
        # @param json_schema [Hash] The JSON schema.
        # @return [Array<String>] Violation list (empty means conformant).
        def validate(data, json_schema)
          schema = stringify_keys(json_schema)
          violations = []
          validate_value(data, schema, "", violations)
          violations
        end

        # Build the payload passed to RubyLLM::Chat#with_schema for native
        # structured output.
        #
        # The schema is passed through unchanged. `strict` is always `false`
        # because enabling OpenAI strict mode would require rewriting existing
        # schemas (all properties required + null-union handling). Even with
        # strict disabled, providers follow the schema closely and the
        # conformance/validation pipeline catches any residual deviation.
        # @param json_schema [Hash] The JSON schema, passed through unchanged.
        # @param name [String] Schema identifier (only [a-zA-Z0-9_-]).
        # @return [Hash] `{ name:, schema:, strict: false }`.
        def native_schema_payload(json_schema, name: "response")
          { name: name, schema: json_schema, strict: false }
        end

        private

        # Resolve the response into a Hash/Array, applying a single parse-fix
        # retry for String responses when a chat_method is available.
        # @return [Hash, Array]
        # @raise [JSON::ParserError] if parsing ultimately fails.
        def parsed_data_from(response, json_schema:, chat_method:, messages:)
          return response if response.is_a?(Hash) || response.is_a?(Array)
          parse_json_from_response(response)
        rescue JSON::ParserError
          raise unless chat_method && messages
          fixed = request_llm_correction(
            messages: messages,
            json_schema: json_schema,
            chat_method: chat_method,
            problem: unparseable_response_problem(response)
          )
          parse_json_from_response(fixed)
        end

        # Conform and validate data against the schema, requesting a single
        # regeneration on violations when a chat_method is available.
        # @return [Object] The conformed, valid value.
        # @raise [SchemaViolationError] if violations cannot be resolved.
        def conform_and_validate(data, json_schema:, chat_method:, messages:)
          conformed = conform_to_schema(data, json_schema)
          violations = validate(conformed, json_schema)
          return conformed if violations.empty?

          return raise_schema_violation(conformed, violations) unless chat_method && messages

          regenerated = request_llm_correction(
            messages: messages,
            json_schema: json_schema,
            chat_method: chat_method,
            problem: schema_violation_problem(conformed, violations)
          )
          reg_data = regenerated.is_a?(String) ? parse_json_from_response(regenerated) : regenerated
          reg_conformed = conform_to_schema(reg_data, json_schema)
          reg_violations = validate(reg_conformed, json_schema)
          return reg_conformed if reg_violations.empty?

          raise_schema_violation(reg_conformed, reg_violations)
        end

        # Log the unresolved response and violations, then raise.
        # @return [void]
        # @raise [SchemaViolationError]
        def raise_schema_violation(data, violations)
          ai_helper_logger.error(
            "Schema violation could not be resolved. " \
            "Response: #{data.inspect}. Violations: #{violations.join('; ')}"
          )
          raise SchemaViolationError.new(
            "LLM response did not conform to the JSON schema after conformance and validation",
            violations
          )
        end

        # Request a correction from the LLM by embedding the problem description
        # and schema into a retry prompt. Generalized for both parse failures
        # and schema violations.
        # @param messages [Array<Hash>] Original messages.
        # @param json_schema [Hash] The JSON schema.
        # @param chat_method [Proc] The chat method to call.
        # @param problem [String] Human-readable problem description.
        # @return [String] The raw LLM response.
        def request_llm_correction(messages:, json_schema:, chat_method:, problem:)
          prompt = <<~PROMPT
            The previous response did not satisfy the expected JSON structure.

            #{problem}

            Expected JSON Schema:
            ```json
            #{JSON.pretty_generate(json_schema)}
            ```

            Please output ONLY a valid JSON value that matches the schema exactly. No additional text.
          PROMPT

          new_messages = messages.dup
          new_messages << { role: "user", content: prompt }
          chat_method.call(new_messages)
        end

        # Build the problem description for an unparseable response.
        # @param response [String] The unparseable response.
        # @return [String]
        def unparseable_response_problem(response)
          <<~MSG
            The following response was supposed to be a valid JSON value but it could not be parsed.

            Response:
            #{response}
          MSG
        end

        # Build the problem description for a schema violation.
        # @param data [Object] The conformed value.
        # @param violations [Array<String>] The detected violations.
        # @return [String]
        def schema_violation_problem(data, violations)
          <<~MSG
            The response was parsed as JSON but violates the schema. The following problems were detected:

            #{violations.map { |v| "- #{v}" }.join("\n")}

            Current response:
            #{JSON.generate(data) rescue data.inspect}
          MSG
        end

        # Recursively conform a value to its schema.
        # @param data [Object]
        # @param schema [Hash] String-keyed schema.
        # @return [Object] A new conformed value.
        def conform_value(data, schema)
          type = schema["type"]
          if data.is_a?(Array)
            return wrap_bare_array(data, schema) if type == "object" && single_array_property?(schema)
            return conform_array(data, schema) if type == "array"
            return data
          end
          return conform_object(data, schema) if data.is_a?(Hash) && type == "object"
          data
        end

        # Wrap a bare array into the single array-type property.
        # @param data [Array]
        # @param schema [Hash] Object schema with one array property.
        # @return [Hash]
        def wrap_bare_array(data, schema)
          prop_name = schema["properties"].keys.first
          { prop_name => conform_array(data, schema["properties"][prop_name]) }
        end

        # Conform each element of an array against the items schema.
        # @param data [Array]
        # @param schema [Hash] Array schema.
        # @return [Array]
        def conform_array(data, schema)
          items_schema = schema["items"]
          return data unless items_schema
          data.map { |item| conform_value(item, items_schema) }
        end

        # Conform an object by removing undeclared keys and recursing.
        # @param data [Hash]
        # @param schema [Hash] Object schema.
        # @return [Hash]
        def conform_object(data, schema)
          properties = schema["properties"] || {}
          result = {}
          data.each do |key, value|
            next unless properties.key?(key)
            result[key] = conform_value(value, properties[key])
          end
          result
        end

        # Whether the object schema has exactly one property of array type.
        # @param schema [Hash]
        # @return [Boolean]
        def single_array_property?(schema)
          props = schema["properties"]
          return false unless props.is_a?(Hash) && props.size == 1
          prop_schema = props.values.first
          prop_schema.is_a?(Hash) && prop_schema["type"] == "array"
        end

        # Recursively validate a value against its schema, appending violations.
        # @param data [Object]
        # @param schema [Hash] String-keyed schema.
        # @param path [String] Current JSON path.
        # @param violations [Array<String>] Accumulator.
        # @return [void]
        def validate_value(data, schema, path, violations)
          type = schema["type"]
          if type && !type_matches?(data, type)
            violations << "#{path}: expected #{type}, got #{type_label(data)}"
            return
          end
          case type
          when "object" then validate_object(data, schema, path, violations)
          when "array" then validate_array(data, schema, path, violations)
          end
        end

        # Validate an object: required keys and declared properties.
        # @param data [Object]
        # @param schema [Hash]
        # @param path [String]
        # @param violations [Array<String>]
        # @return [void]
        def validate_object(data, schema, path, violations)
          (schema["required"] || []).each do |key|
            unless data.is_a?(Hash) && data.key?(key)
              violations << "#{join_path(path, key)}: required key missing"
            end
          end
          properties = schema["properties"] || {}
          return unless data.is_a?(Hash)
          data.each do |key, value|
            next unless properties.key?(key)
            validate_value(value, properties[key], join_path(path, key), violations)
          end
        end

        # Validate each array element against the items schema.
        # @param data [Array]
        # @param schema [Hash]
        # @param path [String]
        # @param violations [Array<String>]
        # @return [void]
        def validate_array(data, schema, path, violations)
          items_schema = schema["items"]
          return unless items_schema
          data.each_with_index do |item, index|
            validate_value(item, items_schema, "#{path}[#{index}]", violations)
          end
        end

        # Join a base path with a key (no leading dot at the root).
        # @param path [String]
        # @param key [String, Symbol]
        # @return [String]
        def join_path(path, key)
          path.empty? ? key.to_s : "#{path}.#{key}"
        end

        # Whether a value matches a JSON schema type.
        # @param data [Object]
        # @param type [String]
        # @return [Boolean]
        def type_matches?(data, type)
          case type
          when "string" then data.is_a?(String)
          when "integer" then data.is_a?(Integer)
          when "number" then data.is_a?(Numeric)
          when "boolean" then [ true, false ].include?(data)
          when "array" then data.is_a?(Array)
          when "object" then data.is_a?(Hash)
          else true
          end
        end

        # Human-readable label for a value's type, used in violation messages.
        # @param data [Object]
        # @return [String]
        def type_label(data)
          return "Boolean" if [ true, false ].include?(data)
          data.class.name
        end

        # Recursively convert all Hash keys to strings.
        # @param obj [Object]
        # @return [Object] A new object with string keys.
        def stringify_keys(obj)
          case obj
          when Hash
            obj.to_h { |k, v| [ k.to_s, stringify_keys(v) ] }
          when Array
            obj.map { |v| stringify_keys(v) }
          else
            obj
          end
        end

        # Extract and parse JSON from a response string.
        # Handles JSON wrapped in ```json ... ``` code blocks.
        # @param response [String] The raw response
        # @return [Hash, Array] Parsed JSON
        # @raise [JSON::ParserError] If no valid JSON is found
        def parse_json_from_response(response)
          return JSON.parse(response.strip) if response.strip.start_with?("{", "[")

          # Try to extract from ```json ... ``` or ``` ... ``` blocks
          json_match = response.match(/```(?:json)?\s*\n?(.*?)\n?\s*```/m)
          return JSON.parse(json_match[1].strip) if json_match

          # Fall back to direct parse
          JSON.parse(response.strip)
        end
      end
    end
  end
end
