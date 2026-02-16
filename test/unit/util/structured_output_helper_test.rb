# frozen_string_literal: true

require_relative "../../test_helper"

class StructuredOutputHelperTest < ActiveSupport::TestCase
  include RedmineAiHelper

  setup do
    @json_schema = {
      type: "object",
      properties: {
        goal: {
          type: "string",
          description: "A concise goal",
        },
        required_flag: {
          type: "boolean",
          description: "Whether steps are required",
        },
      },
      required: ["goal", "required_flag"],
    }
  end

  context "get_format_instructions" do
    should "return instructions string containing the JSON schema" do
      instructions = Util::StructuredOutputHelper.get_format_instructions(@json_schema)

      assert instructions.is_a?(String)
      assert_includes instructions, "JSON Schema"
      assert_includes instructions, '"goal"'
      assert_includes instructions, '"required_flag"'
    end

    should "include markdown codeblock with schema" do
      instructions = Util::StructuredOutputHelper.get_format_instructions(@json_schema)

      assert_includes instructions, "```json"
      assert_includes instructions, "```"
    end
  end

  context "parse" do
    should "parse valid JSON response directly" do
      response = '{"goal": "Test goal", "required_flag": true}'

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema,
      )

      assert_equal "Test goal", result["goal"]
      assert_equal true, result["required_flag"]
    end

    should "parse JSON wrapped in markdown code block" do
      response = <<~RESPONSE
        Here is the result:

        ```json
        {"goal": "Test goal", "required_flag": false}
        ```

        Let me know if you need more.
      RESPONSE

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema,
      )

      assert_equal "Test goal", result["goal"]
      assert_equal false, result["required_flag"]
    end

    should "parse JSON wrapped in plain code block" do
      response = "```\n{\"goal\": \"Test\", \"required_flag\": true}\n```"

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema,
      )

      assert_equal "Test", result["goal"]
    end

    should "retry with LLM when initial parse fails" do
      bad_response = "This is not valid JSON at all"
      fixed_response = '{"goal": "Fixed goal", "required_flag": true}'

      mock_chat_method = lambda do |messages|
        fixed_response
      end

      result = Util::StructuredOutputHelper.parse(
        response: bad_response,
        json_schema: @json_schema,
        chat_method: mock_chat_method,
        messages: [{ role: "user", content: "test" }],
      )

      assert_equal "Fixed goal", result["goal"]
    end

    should "raise error when parse fails and no chat_method provided" do
      bad_response = "Not JSON"

      assert_raises(JSON::ParserError) do
        Util::StructuredOutputHelper.parse(
          response: bad_response,
          json_schema: @json_schema,
        )
      end
    end

    should "raise error when retry also fails" do
      bad_response = "Not JSON"
      also_bad_response = "Still not JSON"

      mock_chat_method = lambda do |messages|
        also_bad_response
      end

      assert_raises(JSON::ParserError) do
        Util::StructuredOutputHelper.parse(
          response: bad_response,
          json_schema: @json_schema,
          chat_method: mock_chat_method,
          messages: [{ role: "user", content: "test" }],
        )
      end
    end

    should "parse array-type JSON schema response" do
      array_schema = {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" },
          },
        },
      }

      response = '[{"name": "item1"}, {"name": "item2"}]'

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: array_schema,
      )

      assert result.is_a?(Array)
      assert_equal 2, result.length
      assert_equal "item1", result[0]["name"]
    end

    should "handle response with extra whitespace" do
      response = "  \n  {\"goal\": \"Trimmed\", \"required_flag\": true}  \n  "

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema,
      )

      assert_equal "Trimmed", result["goal"]
    end
  end

  context "parse_json_from_response" do
    should "extract JSON from response with surrounding text" do
      response = "Here is the output:\n{\"goal\": \"Test\"}\nDone."

      # Since parse_json_from_response is private, test through parse
      result = Util::StructuredOutputHelper.parse(
        response: "{\"goal\": \"Direct\", \"required_flag\": true}",
        json_schema: @json_schema,
      )

      assert_equal "Direct", result["goal"]
    end
  end
end
