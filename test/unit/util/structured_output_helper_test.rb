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
          description: "A concise goal"
        },
        required_flag: {
          type: "boolean",
          description: "Whether steps are required"
        }
      },
      required: [ "goal", "required_flag" ]
    }
  end

  context "get_format_instructions" do
    should "return instructions string containing the JSON schema" do
      instructions = Util::StructuredOutputHelper.get_format_instructions(@json_schema)

      assert_kind_of String, instructions
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
        json_schema: @json_schema
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
        json_schema: @json_schema
      )

      assert_equal "Test goal", result["goal"]
      assert_equal false, result["required_flag"]
    end

    should "parse JSON wrapped in plain code block" do
      response = "```\n{\"goal\": \"Test\", \"required_flag\": true}\n```"

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema
      )

      assert_equal "Test", result["goal"]
    end

    should "retry with LLM when initial parse fails" do
      bad_response = "This is not valid JSON at all"
      fixed_response = '{"goal": "Fixed goal", "required_flag": true}'

      mock_chat_method = lambda do |_messages|
        fixed_response
      end

      result = Util::StructuredOutputHelper.parse(
        response: bad_response,
        json_schema: @json_schema,
        chat_method: mock_chat_method,
        messages: [ { role: "user", content: "test" } ]
      )

      assert_equal "Fixed goal", result["goal"]
    end

    should "raise error when parse fails and no chat_method provided" do
      bad_response = "Not JSON"

      assert_raises(JSON::ParserError) do
        Util::StructuredOutputHelper.parse(
          response: bad_response,
          json_schema: @json_schema
        )
      end
    end

    should "raise error when retry also fails" do
      bad_response = "Not JSON"
      also_bad_response = "Still not JSON"

      mock_chat_method = lambda do |_messages|
        also_bad_response
      end

      assert_raises(JSON::ParserError) do
        Util::StructuredOutputHelper.parse(
          response: bad_response,
          json_schema: @json_schema,
          chat_method: mock_chat_method,
          messages: [ { role: "user", content: "test" } ]
        )
      end
    end

    should "parse array-type JSON schema response" do
      array_schema = {
        type: "array",
        items: {
          type: "object",
          properties: {
            name: { type: "string" }
          }
        }
      }

      response = '[{"name": "item1"}, {"name": "item2"}]'

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: array_schema
      )

      assert_kind_of Array, result
      assert_equal 2, result.length
      assert_equal "item1", result[0]["name"]
    end

    should "handle response with extra whitespace" do
      response = "  \n  {\"goal\": \"Trimmed\", \"required_flag\": true}  \n  "

      result = Util::StructuredOutputHelper.parse(
        response: response,
        json_schema: @json_schema
      )

      assert_equal "Trimmed", result["goal"]
    end
  end

  context "parse_json_from_response" do
    should "extract JSON from response with surrounding text" do
      # Since parse_json_from_response is private, test through parse
      result = Util::StructuredOutputHelper.parse(
        response: "{\"goal\": \"Direct\", \"required_flag\": true}",
        json_schema: @json_schema
      )

      assert_equal "Direct", result["goal"]
    end
  end

  context "conform_to_schema - bare array wrapping" do
    setup do
      @sub_issues_schema = {
        type: "object",
        properties: {
          sub_issues: {
            type: "array",
            items: {
              type: "object",
              properties: {
                subject: { type: "string" },
                tracker_id: { type: "integer" }
              },
              required: [ "subject", "tracker_id" ]
            }
          }
        }
      }
    end

    should "wrap a bare array into the single array-type property" do
      data = [ { "subject" => "a", "tracker_id" => 1 }, { "subject" => "b", "tracker_id" => 2 } ]

      result = Util::StructuredOutputHelper.conform_to_schema(data, @sub_issues_schema)

      assert_kind_of Hash, result
      assert_kind_of Array, result["sub_issues"]
      assert_equal 2, result["sub_issues"].length
      assert_equal "a", result["sub_issues"][0]["subject"]
    end

    should "not wrap a bare array when schema object has multiple properties" do
      schema = {
        type: "object",
        properties: {
          a: { type: "array", items: { type: "string" } },
          b: { type: "string" }
        }
      }
      data = [ "x", "y" ]

      result = Util::StructuredOutputHelper.conform_to_schema(data, schema)

      # Not wrapped (single array property condition not met) — validate will flag it
      assert_equal [ "x", "y" ], result
    end

    should "not wrap a bare array when the single property is not array type" do
      schema = {
        type: "object",
        properties: {
          name: { type: "string" }
        }
      }
      data = [ 1, 2, 3 ]

      result = Util::StructuredOutputHelper.conform_to_schema(data, schema)

      assert_equal [ 1, 2, 3 ], result
    end
  end

  context "conform_to_schema - undeclared key removal" do
    should "remove undeclared keys recursively from object properties" do
      schema = {
        "type" => "object",
        "properties" => {
          "sub_issues" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => {
                "subject" => { "type" => "string" },
                "tracker_id" => { "type" => "integer" }
              },
              "required" => [ "subject" ]
            }
          }
        }
      }
      data = {
        "sub_issues" => [
          { "subject" => "ok", "tracker_id" => 1, "title" => "undeclared" },
          { "subject" => "ok2", "bogus" => 99 }
        ]
      }

      result = Util::StructuredOutputHelper.conform_to_schema(data, schema)

      assert_equal "ok", result["sub_issues"][0]["subject"]
      assert_equal 1, result["sub_issues"][0]["tracker_id"]
      assert_nil result["sub_issues"][0]["title"]
      assert_nil result["sub_issues"][1]["bogus"]
    end

    should "work with symbol keys in the schema" do
      schema = {
        type: "object",
        properties: {
          goal: { type: "string" }
        },
        required: [ "goal" ]
      }
      data = { goal: "g", extra: "remove me" }

      result = Util::StructuredOutputHelper.conform_to_schema(data, schema)

      assert_equal "g", result["goal"]
      assert_not result.key?("extra")
    end

    should "not mutate the input" do
      schema = { "type" => "object", "properties" => { "a" => { "type" => "string" } } }
      data = { "a" => "1", "b" => "2" }

      Util::StructuredOutputHelper.conform_to_schema(data, schema)

      assert_equal({ "a" => "1", "b" => "2" }, data)
    end
  end

  context "validate" do
    should "return empty violations for compliant data" do
      schema = {
        "type" => "object",
        "properties" => { "goal" => { "type" => "string" }, "flag" => { "type" => "boolean" } },
        "required" => [ "goal", "flag" ]
      }
      data = { "goal" => "x", "flag" => true }

      assert_equal [], Util::StructuredOutputHelper.validate(data, schema)
    end

    should "detect missing required keys" do
      schema = {
        "type" => "object",
        "properties" => { "goal" => { "type" => "string" } },
        "required" => [ "goal" ]
      }
      data = {}

      violations = Util::StructuredOutputHelper.validate(data, schema)

      assert_equal 1, violations.length
      assert_match(/goal: required key missing/, violations.first)
    end

    should "detect type mismatch for integer vs string" do
      schema = {
        "type" => "object",
        "properties" => { "tracker_id" => { "type" => "integer" } },
        "required" => [ "tracker_id" ]
      }
      data = { "tracker_id" => "not a number" }

      violations = Util::StructuredOutputHelper.validate(data, schema)

      assert_equal 1, violations.length
      assert_match(/tracker_id: expected integer, got String/, violations.first)
    end

    should "tolerate null for an optional property" do
      schema = {
        "type" => "object",
        "properties" => { "subject" => { "type" => "string" }, "fixed_version_id" => { "type" => "integer" }, "due_date" => { "type" => "string" } },
        "required" => [ "subject" ]
      }
      data = { "subject" => "x", "fixed_version_id" => nil, "due_date" => nil }

      assert_equal [], Util::StructuredOutputHelper.validate(data, schema)
    end

    should "still detect type mismatch for null on a required property" do
      schema = {
        "type" => "object",
        "properties" => { "tracker_id" => { "type" => "integer" } },
        "required" => [ "tracker_id" ]
      }
      data = { "tracker_id" => nil }

      violations = Util::StructuredOutputHelper.validate(data, schema)

      assert_equal 1, violations.length
      assert_match(/tracker_id: expected integer, got NilClass/, violations.first)
    end

    should "map number to Numeric and accept floats" do
      schema = { "type" => "object", "properties" => { "n" => { "type" => "number" } }, "required" => [ "n" ] }

      assert_empty Util::StructuredOutputHelper.validate({ "n" => 1.5 }, schema)
      assert_empty Util::StructuredOutputHelper.validate({ "n" => 3 }, schema)
    end

    should "not coerce types (string integer stays a violation)" do
      schema = { "type" => "object", "properties" => { "n" => { "type" => "integer" } }, "required" => [ "n" ] }
      data = { "n" => "5" }

      assert_not_empty Util::StructuredOutputHelper.validate(data, schema)
    end

    should "accept true and false for boolean" do
      schema = { "type" => "object", "properties" => { "b" => { "type" => "boolean" } }, "required" => [ "b" ] }

      assert_empty Util::StructuredOutputHelper.validate({ "b" => true }, schema)
      assert_empty Util::StructuredOutputHelper.validate({ "b" => false }, schema)
    end

    should "validate recursively in nested objects and array items" do
      schema = {
        "type" => "object",
        "properties" => {
          "sub_issues" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "properties" => { "subject" => { "type" => "string" }, "tracker_id" => { "type" => "integer" } },
              "required" => [ "subject", "tracker_id" ]
            }
          }
        }
      }
      data = { "sub_issues" => [ { "subject" => "ok", "tracker_id" => "bad" }, {} ] }

      violations = Util::StructuredOutputHelper.validate(data, schema)

      # item[0] tracker_id type mismatch + item[1] missing subject + tracker_id
      paths = violations.join("\n")
      assert_match(/sub_issues\[0\]\.tracker_id: expected integer, got String/, paths)
      assert_match(/sub_issues\[1\]\.subject: required key missing/, paths)
      assert_match(/sub_issues\[1\]\.tracker_id: required key missing/, paths)
    end

    should "not validate format or enum" do
      schema = {
        "type" => "object",
        "properties" => { "due_date" => { "type" => "string", "format" => "date" },
                          "conf" => { "type" => "string", "enum" => [ "high", "low" ] } },
        "required" => [ "due_date", "conf" ]
      }
      data = { "due_date" => "not-a-date", "conf" => "medium" }

      assert_empty Util::StructuredOutputHelper.validate(data, schema)
    end

    should "flag a bare array when schema expects object" do
      schema = { "type" => "object", "properties" => { "a" => { "type" => "string" } } }

      violations = Util::StructuredOutputHelper.validate([ 1, 2 ], schema)

      assert_equal 1, violations.length
      assert_match(/expected object, got Array/, violations.first)
    end
  end

  context "native_schema_payload" do
    should "return a payload with name, schema, and strict: false" do
      schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } } }

      payload = Util::StructuredOutputHelper.native_schema_payload(schema)

      assert_equal "response", payload[:name]
      assert_equal schema, payload[:schema]
      assert_equal false, payload[:strict]
    end

    should "use the provided name when given" do
      schema = { "type" => "array" }

      payload = Util::StructuredOutputHelper.native_schema_payload(schema, name: "sub_issues")

      assert_equal "sub_issues", payload[:name]
      assert_equal schema, payload[:schema]
      assert_equal false, payload[:strict]
    end

    should "pass the json_schema through unchanged" do
      schema = { type: "object", properties: { x: { type: "integer" } }, required: [ "x" ] }

      payload = Util::StructuredOutputHelper.native_schema_payload(schema)

      assert_equal schema, payload[:schema]
    end

    should "always set strict to false even if input suggests otherwise" do
      payload = Util::StructuredOutputHelper.native_schema_payload({ "type" => "object" }, name: "x")

      assert_equal false, payload[:strict]
    end
  end

  context "SchemaViolationError" do
    should "be a StandardError with a violations attribute" do
      error = Util::StructuredOutputHelper::SchemaViolationError.new("msg", [ "v1", "v2" ])

      assert_kind_of StandardError, error
      assert_equal "msg", error.message
      assert_equal [ "v1", "v2" ], error.violations
    end
  end

  context "parse with Hash/Array input (native path)" do
    should "skip JSON parsing and apply conform + validate for Hash input" do
      schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } }, "required" => [ "goal" ] }
      data = { "goal" => "g", "extra" => "x" }

      result = Util::StructuredOutputHelper.parse(response: data, json_schema: schema)

      assert_equal "g", result["goal"]
      assert_not result.key?("extra")
    end

    should "conform a bare array Hash response via wrap" do
      schema = {
        "type" => "object",
        "properties" => { "sub_issues" => { "type" => "array", "items" => { "type" => "object", "properties" => { "subject" => { "type" => "string" } }, "required" => [ "subject" ] } } }
      }
      # Native path returns a bare Array
      result = Util::StructuredOutputHelper.parse(response: [ { "subject" => "a" } ], json_schema: schema)

      assert_kind_of Hash, result
      assert_equal "a", result["sub_issues"][0]["subject"]
    end

    should "raise SchemaViolationError immediately when no chat_method and violations found" do
      schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } }, "required" => [ "goal" ] }

      assert_raises(Util::StructuredOutputHelper::SchemaViolationError) do
        Util::StructuredOutputHelper.parse(response: { "other" => "x" }, json_schema: schema)
      end
    end
  end

  context "parse schema regeneration" do
    setup do
      @schema = {
        "type" => "object",
        "properties" => { "goal" => { "type" => "string" } },
        "required" => [ "goal" ]
      }
    end

    should "request regeneration exactly once when violations found and chat_method provided" do
      call_count = 0
      mock_chat_method = lambda do |_messages|
        call_count += 1
        # Regenerated response is compliant
        '{"goal": "fixed"}'
      end

      result = Util::StructuredOutputHelper.parse(
        response: '{"other": "missing goal"}',
        json_schema: @schema,
        chat_method: mock_chat_method,
        messages: [ { role: "user", content: "test" } ]
      )

      assert_equal 1, call_count
      assert_equal "fixed", result["goal"]
    end

    should "raise SchemaViolationError when regeneration still violates" do
      call_count = 0
      mock_chat_method = lambda do |_messages|
        call_count += 1
        '{"still_no_goal": "x"}'
      end

      error = assert_raises(Util::StructuredOutputHelper::SchemaViolationError) do
        Util::StructuredOutputHelper.parse(
          response: '{"other": "x"}',
          json_schema: @schema,
          chat_method: mock_chat_method,
          messages: [ { role: "user", content: "test" } ]
        )
      end

      assert_equal 1, call_count
      assert_not_empty error.violations
    end

    should "count parse-fix and schema-regeneration independently (each at most once)" do
      schema = {
        "type" => "object",
        "properties" => { "goal" => { "type" => "string" } },
        "required" => [ "goal" ]
      }
      call_count = 0
      mock_chat_method = lambda do |_messages|
        call_count += 1
        if call_count == 1
          # Parse-fix: returns parseable but schema-nonconforming JSON
          '{"other": "x"}'
        else
          # Schema-regeneration: still nonconforming
          '{"still_no_goal": "x"}'
        end
      end

      assert_raises(Util::StructuredOutputHelper::SchemaViolationError) do
        Util::StructuredOutputHelper.parse(
          response: "not parseable at all {{{",
          json_schema: schema,
          chat_method: mock_chat_method,
          messages: [ { role: "user", content: "test" } ]
        )
      end

      # parse-fix used 1 call; schema-regeneration used 1 call = 2 total
      assert_equal 2, call_count
    end
  end

  context "parse logging" do
    should "log original response and violations to ai_helper_logger before raising" do
      schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } }, "required" => [ "goal" ] }
      logger = mock("ai_helper_logger")
      logger.expects(:error).with { |msg| msg.to_s.include?("goal") && msg.to_s.include?("required key missing") }.at_least_once
      Util::StructuredOutputHelper.stubs(:ai_helper_logger).returns(logger)

      assert_raises(Util::StructuredOutputHelper::SchemaViolationError) do
        Util::StructuredOutputHelper.parse(response: { "other" => "x" }, json_schema: schema)
      end
    end
  end

  context "array-root schema wrapping (native structured output)" do
    setup do
      @array_schema = {
        "type" => "array",
        "items" => {
          "type" => "object",
          "properties" => { "corrected" => { "type" => "string" } },
          "required" => [ "corrected" ]
        }
      }
    end

    context "array_root_schema?" do
      should "return true for an array-rooted schema" do
        assert Util::StructuredOutputHelper.array_root_schema?(@array_schema)
      end

      should "return false for an object-rooted schema" do
        object_schema = { "type" => "object", "properties" => { "goal" => { "type" => "string" } } }
        assert_not Util::StructuredOutputHelper.array_root_schema?(object_schema)
      end

      should "work with symbol-keyed schemas" do
        assert Util::StructuredOutputHelper.array_root_schema?(type: "array", items: { type: "string" })
      end
    end

    context "wrap_array_root_schema" do
      should "wrap the array schema under the value property, required" do
        wrapped = Util::StructuredOutputHelper.wrap_array_root_schema(@array_schema)

        assert_equal "object", wrapped["type"]
        assert_equal @array_schema, wrapped["properties"]["value"]
        assert_equal [ "value" ], wrapped["required"]
      end
    end

    context "unwrap_array_root" do
      should "unwrap a Hash response with the value key" do
        result = Util::StructuredOutputHelper.unwrap_array_root({ "value" => [ { "corrected" => "the" } ] })

        assert_equal [ { "corrected" => "the" } ], result
      end

      should "unwrap a String JSON response with the value key" do
        result = Util::StructuredOutputHelper.unwrap_array_root('{"value": [{"corrected": "the"}]}')

        assert_equal [ { "corrected" => "the" } ], result
      end

      should "return the response unchanged when the value key is absent" do
        response = { "other" => [ 1, 2 ] }

        assert_equal response, Util::StructuredOutputHelper.unwrap_array_root(response)
      end

      should "return the response unchanged when it is already a bare Array" do
        response = [ { "corrected" => "the" } ]

        assert_equal response, Util::StructuredOutputHelper.unwrap_array_root(response)
      end

      should "return the response unchanged when the String is not parseable" do
        response = "not parseable {{{"

        assert_equal response, Util::StructuredOutputHelper.unwrap_array_root(response)
      end
    end

    context "end-to-end wrap -> unwrap -> parse" do
      should "produce a schema-conformant array from a wrapped native response" do
        native_schema = Util::StructuredOutputHelper.wrap_array_root_schema(@array_schema)
        payload = Util::StructuredOutputHelper.native_schema_payload(native_schema)
        assert_equal "object", payload[:schema]["type"]

        native_response = { "value" => [ { "corrected" => "the", "extra" => "strip me" } ] }
        unwrapped = Util::StructuredOutputHelper.unwrap_array_root(native_response)

        result = Util::StructuredOutputHelper.parse(response: unwrapped, json_schema: @array_schema)

        assert_equal [ { "corrected" => "the" } ], result
      end
    end
  end
end
