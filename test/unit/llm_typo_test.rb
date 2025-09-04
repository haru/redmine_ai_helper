require File.expand_path('../../test_helper', __FILE__)

class LlmTypoTest < ActiveSupport::TestCase
  fixtures :projects, :users

  def setup
    @project = projects(:projects_001)
    @llm = RedmineAiHelper::Llm.new
  end

  def test_check_typos_success
    mock_agent = mock('documentation_agent')
    mock_suggestions = [
      {
        "original" => "typo",
        "corrected" => "typos",
        "position" => 5,
        "length" => 4,
        "reason" => "Grammar correction",
        "confidence" => "high"
      }
    ]
    
    mock_agent.expects(:check_typos).with(
      text: "Test typo in text",
      context_type: 'general',
      max_suggestions: 10
    ).returns(mock_suggestions)
    
    # Mock LangfuseWrapper
    mock_langfuse = mock('langfuse')
    mock_langfuse.expects(:create_span).with(name: "typo_check", input: "Test typo in text")
    mock_langfuse.expects(:finish_current_span).with(output: mock_suggestions)
    mock_langfuse.expects(:flush)
    
    RedmineAiHelper::LangfuseUtil::LangfuseWrapper.stubs(:new).returns(mock_langfuse)
    RedmineAiHelper::Agents::DocumentationAgent.stubs(:new).returns(mock_agent)
    
    result = @llm.check_typos(
      text: "Test typo in text",
      context_type: 'general',
      project: @project,
      max_suggestions: 10
    )
    
    assert_equal mock_suggestions, result
  end

  def test_check_typos_with_error
    mock_langfuse = mock('langfuse')
    # The create_span call never happens because the error occurs in DocumentationAgent.new
    
    RedmineAiHelper::LangfuseUtil::LangfuseWrapper.stubs(:new).returns(mock_langfuse)
    RedmineAiHelper::Agents::DocumentationAgent.stubs(:new).raises(StandardError.new("Test error"))
    
    # Mock logger to verify error logging
    mock_logger = mock('logger')
    mock_logger.expects(:info).with("Starting typo check: context_type=issue, text_length=9")
    mock_logger.expects(:error).with(regexp_matches(/Typo check error:/))
    @llm.stubs(:ai_helper_logger).returns(mock_logger)
    
    result = @llm.check_typos(
      text: "Test text",
      context_type: 'issue',
      project: @project
    )
    
    assert_equal [], result
  end

  def test_check_typos_default_parameters
    mock_agent = mock('documentation_agent')
    mock_agent.expects(:check_typos).with(
      text: "Test text",
      context_type: 'general',
      max_suggestions: 10
    ).returns([])
    
    mock_langfuse = mock('langfuse')
    mock_langfuse.expects(:create_span).with(name: "typo_check", input: "Test text")
    mock_langfuse.expects(:finish_current_span).with(output: [])
    mock_langfuse.expects(:flush)
    
    RedmineAiHelper::LangfuseUtil::LangfuseWrapper.stubs(:new).returns(mock_langfuse)
    RedmineAiHelper::Agents::DocumentationAgent.stubs(:new).returns(mock_agent)
    
    result = @llm.check_typos(text: "Test text")
    
    assert_equal [], result
  end
end