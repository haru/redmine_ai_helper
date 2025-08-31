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

    @agent.stubs(:chat).returns("mock response")
    
    # Mock the StructuredOutputParser and OutputFixingParser
    parser_mock = mock('parser')
    parser_mock.stubs(:get_format_instructions).returns("format instructions")
    Langchain::OutputParsers::StructuredOutputParser.stubs(:from_json_schema).returns(parser_mock)
    
    fix_parser_mock = mock('fix_parser')
    fix_parser_mock.stubs(:parse).returns(mock_response)
    Langchain::OutputParsers::OutputFixingParser.stubs(:from_llm).returns(fix_parser_mock)
    
    # Mock the client method
    @agent.stubs(:client).returns(mock('client'))
    
    result = @agent.check_typos(text: "teh quick brown fox", context_type: "test")
    assert_equal mock_response, result
  end

  def test_check_typos_with_empty_text
    parser_mock = mock('parser')
    parser_mock.stubs(:get_format_instructions).returns("format instructions")
    Langchain::OutputParsers::StructuredOutputParser.stubs(:from_json_schema).returns(parser_mock)
    
    fix_parser_mock = mock('fix_parser')
    fix_parser_mock.stubs(:parse).returns([])
    Langchain::OutputParsers::OutputFixingParser.stubs(:from_llm).returns(fix_parser_mock)
    
    @agent.stubs(:client).returns(mock('client'))
    @agent.stubs(:chat).returns("empty response")
    
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
end