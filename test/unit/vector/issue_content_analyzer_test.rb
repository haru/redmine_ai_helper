require File.expand_path("../../../test_helper", __FILE__)

class RedmineAiHelper::Vector::IssueContentAnalyzerTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :journals

  context "IssueContentAnalyzer" do
    setup do
      @issue = Issue.find(1)
      @mock_llm_provider = mock("llm_provider")
      @mock_llm_provider.stubs(:model_name).returns("gpt-4")
      @mock_llm_provider.stubs(:create_chat)
      @mock_logger = mock("logger")
      @mock_logger.stubs(:debug)
      @mock_logger.stubs(:info)
      @mock_logger.stubs(:warn)
      @mock_logger.stubs(:error)
    end

    context "#analyze" do
      should "analyze issue and return summary and keywords" do
        valid_response = {
          "summary" => "This issue is about a bug in the login system. The user cannot log in due to a session timeout error.",
          "keywords" => ["login", "session timeout", "authentication", "bug"]
        }.to_json

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(valid_response)

        result = analyzer.analyze(@issue)

        assert result[:summary].present?
        assert result[:keywords].is_a?(Array)
        assert_equal 4, result[:keywords].length
        assert_includes result[:keywords], "login"
        assert_includes result[:keywords], "session timeout"
      end

      should "parse valid JSON response from LLM" do
        valid_json = {
          "summary" => "A test summary for the issue.",
          "keywords" => ["keyword1", "keyword2", "keyword3"]
        }.to_json

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(valid_json)

        result = analyzer.analyze(@issue)

        assert_equal "A test summary for the issue.", result[:summary]
        assert_equal ["keyword1", "keyword2", "keyword3"], result[:keywords]
      end

      should "parse JSON wrapped in markdown code block" do
        json_data = {
          "summary" => "This is a summary extracted from markdown.",
          "keywords" => ["markdown", "code block", "json"]
        }
        json_in_code_block = <<~RESPONSE
          Here is the analysis:

          ```json
          #{json_data.to_json}
          ```

          Let me know if you need more details.
        RESPONSE

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(json_in_code_block)

        result = analyzer.analyze(@issue)

        assert_equal "This is a summary extracted from markdown.", result[:summary]
        assert_equal ["markdown", "code block", "json"], result[:keywords]
      end

      should "return empty result when LLM call fails" do
        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).raises(StandardError.new("API connection failed"))

        result = analyzer.analyze(@issue)

        assert_equal "", result[:summary]
        assert_equal [], result[:keywords]
      end

      should "return empty result when response is not valid JSON" do
        invalid_response = "This is not JSON, just plain text response from the LLM."

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(invalid_response)
        RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).raises(StandardError.new("Failed to parse JSON"))

        result = analyzer.analyze(@issue)

        assert_equal "", result[:summary]
        assert_equal [], result[:keywords]
      end

      should "return empty result when JSON is missing required fields" do
        incomplete_json = {
          "other_field" => "some value"
        }.to_json

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(incomplete_json)

        result = analyzer.analyze(@issue)

        # Should still return a valid structure with empty/default values
        assert_equal "", result[:summary]
        assert_equal [], result[:keywords]
      end

      should "handle empty keywords array in response" do
        response_data = {
          "summary" => "A summary without keywords.",
          "keywords" => []
        }

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(response_data.to_json)

        result = analyzer.analyze(@issue)

        assert_equal "A summary without keywords.", result[:summary]
        assert_equal [], result[:keywords]
      end

      should "handle null summary in response" do
        response_data = {
          "summary" => nil,
          "keywords" => ["keyword1"]
        }

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(response_data.to_json)

        result = analyzer.analyze(@issue)

        assert_equal "", result[:summary]
        assert_equal ["keyword1"], result[:keywords]
      end
    end

    context "#build_prompt" do
      should "build prompt with issue data" do
        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.is_a?(String), "Prompt should be a string"
        assert prompt.include?(@issue.subject), "Prompt should contain issue subject"
      end

      should "include issue description in prompt" do
        @issue.description = "This is a detailed description of the bug."
        @issue.save!

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.include?(@issue.description), "Prompt should contain issue description"
      end

      should "include journal notes in prompt when present" do
        journal = Journal.new(
          journalized: @issue,
          user: User.find(1),
          notes: "This is a comment on the issue."
        )
        journal.save!

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.include?("This is a comment on the issue."), "Prompt should contain journal notes"
      end

      should "handle issue with no description" do
        @issue.description = nil
        @issue.save!

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.is_a?(String), "Prompt should still be a string"
        assert prompt.include?(@issue.subject), "Prompt should contain issue subject"
      end

      should "handle issue with no journals" do
        @issue.journals.destroy_all

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.is_a?(String), "Prompt should still be a string"
      end

      should "include format instructions in prompt" do
        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)

        prompt = analyzer.send(:build_prompt, @issue, "Output JSON with summary and keywords fields.")

        assert prompt.include?("Output JSON with summary and keywords fields."), "Prompt should contain format instructions"
      end
    end

    context "#initialize" do
      should "use provided LLM provider" do
        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)

        assert_equal @mock_llm_provider, analyzer.instance_variable_get(:@llm_provider)
      end

      should "create default LLM provider when not provided" do
        mock_provider = mock("llm_provider")
        RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(mock_provider)

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new

        assert_equal mock_provider, analyzer.instance_variable_get(:@llm_provider)
      end
    end

    context "JSON_SCHEMA" do
      should "use correct JSON schema" do
        schema = RedmineAiHelper::Vector::IssueContentAnalyzer::JSON_SCHEMA

        assert_equal "object", schema[:type]
        assert schema[:properties].key?(:summary)
        assert schema[:properties].key?(:keywords)
        assert_equal "string", schema[:properties][:summary][:type]
        assert_equal "array", schema[:properties][:keywords][:type]
        assert_includes schema[:required], "summary"
        assert_includes schema[:required], "keywords"
      end
    end

    context "edge cases" do
      should "handle very long issue content" do
        long_description = "A" * 10000
        @issue.description = long_description
        @issue.save!

        valid_response = {
          "summary" => "Summary of long content.",
          "keywords" => ["long", "content"]
        }.to_json

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(valid_response)

        result = analyzer.analyze(@issue)

        assert_equal "Summary of long content.", result[:summary]
        assert_equal ["long", "content"], result[:keywords]
      end

      should "handle issue with special characters in content" do
        @issue.subject = "Bug with special chars: <>\"'&"
        @issue.description = "Description with unicode: \u3042\u3044\u3046"
        @issue.save!

        valid_response = {
          "summary" => "Summary with special characters.",
          "keywords" => ["unicode", "special chars"]
        }.to_json

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(valid_response)

        result = analyzer.analyze(@issue)

        assert_equal "Summary with special characters.", result[:summary]
      end

      should "handle JSON response with extra whitespace" do
        response_data = {
          "summary" => "Summary with whitespace.",
          "keywords" => ["test"]
        }
        response_with_whitespace = "  \n  " + response_data.to_json + "  \n  "

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(response_with_whitespace)

        result = analyzer.analyze(@issue)

        assert_equal "Summary with whitespace.", result[:summary]
        assert_equal ["test"], result[:keywords]
      end

      should "handle malformed JSON in markdown code block" do
        malformed_json_in_block = <<~RESPONSE
          ```json
          { "summary": "unclosed string, "keywords": [] }
          ```
        RESPONSE

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(malformed_json_in_block)
        RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).raises(StandardError.new("Failed to parse JSON"))

        result = analyzer.analyze(@issue)

        assert_equal "", result[:summary]
        assert_equal [], result[:keywords]
      end

      should "handle response with multiple JSON blocks and use first valid one" do
        first_block_data = {
          "summary" => "First block summary.",
          "keywords" => ["first"]
        }
        multiple_json_blocks = <<~RESPONSE
          ```json
          #{first_block_data.to_json}
          ```

          Some text in between.

          ```json
          {
            "summary": "Second block summary.",
            "keywords": ["second"]
          }
          ```
        RESPONSE

        analyzer = RedmineAiHelper::Vector::IssueContentAnalyzer.new(llm_provider: @mock_llm_provider)
        analyzer.stubs(:ai_helper_logger).returns(@mock_logger)
        analyzer.stubs(:call_llm).returns(multiple_json_blocks)

        result = analyzer.analyze(@issue)

        # Should use the first valid JSON block
        assert_equal "First block summary.", result[:summary]
        assert_equal ["first"], result[:keywords]
      end
    end
  end
end
