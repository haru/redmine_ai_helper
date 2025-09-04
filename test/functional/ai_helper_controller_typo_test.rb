require File.expand_path('../../test_helper', __FILE__)

class AiHelperControllerTypoTest < ActionController::TestCase
  fixtures :projects, :users, :roles, :members, :member_roles

  def setup
    @controller = AiHelperController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create
    @user = User.find(1)
    @project = projects(:projects_001)
    
    # Enable ai_helper module for the project
    enabled_module = EnabledModule.new
    enabled_module.project_id = @project.id
    enabled_module.name = "ai_helper"
    enabled_module.save!
    
    @request.session[:user_id] = @user.id
  end

  def test_check_typos_for_issue
    mock_llm = mock('llm')
    mock_suggestions = [
      {
        "original" => "tset",
        "corrected" => "test", 
        "position" => 10,
        "length" => 4,
        "reason" => "Spelling mistake",
        "confidence" => "high"
      }
    ]
    mock_llm.expects(:check_typos).with(
      text: "This is a tset text",
      context_type: 'issue',
      project: @project,
      max_suggestions: 10
    ).returns(mock_suggestions)
    
    RedmineAiHelper::Llm.stubs(:new).returns(mock_llm)
    
    post :check_typos, params: {
      id: @project.identifier,
      text: "This is a tset text",
      context_type: 'issue'
    }
    
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.has_key?('suggestions')
    assert_equal mock_suggestions, json_response['suggestions']
  end

  def test_check_typos_with_blank_text
    post :check_typos, params: {
      id: @project.identifier,
      text: "",
      context_type: 'issue'
    }
    
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.has_key?('suggestions')
    assert_equal [], json_response['suggestions']
  end

  def test_check_typos_for_wiki
    mock_llm = mock('llm')
    mock_suggestions = [
      {
        "original" => "pagge",
        "corrected" => "page",
        "position" => 17,
        "length" => 5,
        "reason" => "Spelling mistake",
        "confidence" => "high"
      }
    ]
    mock_llm.expects(:check_typos).with(
      text: "This is a wiki pagge",
      context_type: 'wiki',
      project: @project,
      max_suggestions: 10
    ).returns(mock_suggestions)
    
    RedmineAiHelper::Llm.stubs(:new).returns(mock_llm)
    
    post :check_typos, params: {
      id: @project.identifier,
      text: "This is a wiki pagge",
      context_type: 'wiki'
    }
    
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.has_key?('suggestions')
    assert_equal mock_suggestions, json_response['suggestions']
  end

  def test_check_typos_with_default_context_type
    post :check_typos, params: {
      id: @project.identifier,
      text: ""
    }
    
    assert_response :success
    json_response = JSON.parse(response.body)
    assert json_response.has_key?('suggestions')
    assert_equal [], json_response['suggestions']
  end

  def test_unauthorized_access
    @request.session[:user_id] = nil
    
    post :check_typos, params: {
      id: @project.identifier,
      text: "test",
      context_type: 'issue'
    }
    
    assert_redirected_to '/login?back_url=' + CGI.escape("http://test.host/projects/#{@project.identifier}/ai_helper/check_typos")
  end

  def test_check_typos_without_ai_helper_module
    # Disable ai_helper module
    EnabledModule.where(project_id: @project.id, name: 'ai_helper').destroy_all
    
    post :check_typos, params: {
      id: @project.identifier,
      text: "test",
      context_type: 'issue'
    }
    
    assert_response :forbidden
  end
end