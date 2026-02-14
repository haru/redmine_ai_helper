require File.expand_path('../../../test_helper', __FILE__)

class DocumentationAgentTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @project = projects(:projects_001)
    @agent = RedmineAiHelper::Agents::DocumentationAgent.new(project: @project)
  end

  def test_check_typos_with_valid_text
    mock_response = [
      {
        "original" => "teh",
        "corrected" => "the",
        "position" => 0,
        "length" => 3,
        "reason" => "Spelling mistake",
        "confidence" => "high"
      }
    ]

    @agent.stubs(:chat).returns(mock_response.to_json)
    RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).returns(mock_response)

    result = @agent.check_typos(text: "teh quick brown fox", context_type: "test")
    assert_equal mock_response, result
  end

  def test_check_typos_with_empty_text
    @agent.stubs(:chat).returns("[]")
    RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).returns([])

    result = @agent.check_typos(text: "", context_type: "test")
    assert_equal [], result
  end

  def test_available_tools_returns_empty_array
    assert_equal [], @agent.available_tools
  end

  def test_backstory_returns_prompt
    prompt_mock = mock('prompt')
    @agent.stubs(:load_prompt).with("documentation_agent/backstory").returns(prompt_mock)

    assert_equal prompt_mock, @agent.backstory
  end

  def test_check_typos_validates_and_fixes_incorrect_length
    # Simulate AI returning incorrect length
    mock_response = [
      {
        "original" => "テストしてみたいい",
        "corrected" => "テストしてみたい",
        "position" => 0,
        "length" => 7,  # Incorrect length (AI mistake)
        "reason" => "Typo correction",
        "confidence" => "high"
      }
    ]

    @agent.stubs(:chat).returns(mock_response.to_json)
    RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).returns(mock_response)

    text = "テストしてみたいいと思います"
    result = @agent.check_typos(text: text, context_type: "test")

    # Should fix the length to the actual length of the original text
    assert_equal 1, result.length
    assert_equal "テストしてみたいい", result[0]['original']
    assert_equal "テストしてみたい", result[0]['corrected']
    assert_equal 0, result[0]['position']
    assert_equal 9, result[0]['length']  # Corrected length (9 characters)
  end

  def test_check_typos_skips_unfindable_suggestions
    # Simulate AI returning suggestion for text that doesn't exist
    mock_response = [
      {
        "original" => "nonexistent",
        "corrected" => "corrected",
        "position" => 0,
        "length" => 11,
        "reason" => "Typo correction",
        "confidence" => "high"
      }
    ]

    @agent.stubs(:chat).returns(mock_response.to_json)
    RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).returns(mock_response)

    text = "これは普通のテキストです"
    result = @agent.check_typos(text: text, context_type: "test")

    # Should skip the unfindable suggestion
    assert_equal 0, result.length
  end

  def test_check_typos_skips_identical_original_and_corrected
    # Simulate AI returning suggestion where original and corrected are the same
    mock_response = [
      {
        "original" => "テスト",
        "corrected" => "テスト",  # Same as original
        "position" => 0,
        "length" => 3,
        "reason" => "No change needed",
        "confidence" => "high"
      },
      {
        "original" => "チェク",
        "corrected" => "チェック",  # Different from original
        "position" => 10,
        "length" => 3,
        "reason" => "Typo correction",
        "confidence" => "high"
      }
    ]

    @agent.stubs(:chat).returns(mock_response.to_json)
    RedmineAiHelper::Util::StructuredOutputHelper.stubs(:parse).returns(mock_response)

    text = "これはtypoのチェクのテストです"
    result = @agent.check_typos(text: text, context_type: "test")

    # Should only keep the suggestion where original != corrected
    assert_equal 1, result.length
    assert_equal "チェク", result[0]['original']
    assert_equal "チェック", result[0]['corrected']
  end
end
