require File.expand_path("../../test_helper", __FILE__)

class AiHelperControllerWikiTest < Redmine::ControllerTest
  fixtures :projects, :users, :roles, :members, :member_roles, :wikis, :wiki_pages, :wiki_contents

  setup do
    @controller = AiHelperController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create

    @project = projects(:projects_001)
    @project.enable_module!(:ai_helper)
    @wiki_page = wiki_pages(:wiki_pages_001)

    @user = users(:users_002)
    @request.session[:user_id] = @user.id
    User.current = @user

    # Ensure user has necessary permissions
    role = @user.roles.first
    unless role.permissions.include?(:view_ai_helper)
      role.permissions << :view_ai_helper
      role.save!
    end
    unless role.permissions.include?(:edit_wiki_pages)
      role.permissions << :edit_wiki_pages
      role.save!
    end
  end

  test "suggest_wiki_completion should return success with valid data" do
    RedmineAiHelper::Llm.any_instance.stubs(:generate_wiki_completion).returns("completion text")

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({
           text: "This project documentation",
           cursor_position: 26,
         })

    assert_response :success
    json = JSON.parse(response.body)
    assert json["suggestion"].is_a?(String)
  end

  test "suggest_wiki_completion should require JSON content type" do
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: "text=test"

    assert_response :unsupported_media_type
  end

  test "suggest_wiki_completion should validate JSON format" do
    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier }
    @request.env["RAW_POST_DATA"] = "invalid json"

    assert_response :bad_request
  end

  test "suggest_wiki_completion should require text parameter" do
    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({})

    assert_response :bad_request
  end

  test "suggest_wiki_completion should validate text length" do
    long_text = "x" * 10001
    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({ text: long_text })

    assert_response :bad_request
  end

  test "suggest_wiki_completion should validate cursor position" do
    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({
           text: "test",
           cursor_position: 10,
         })

    assert_response :bad_request
  end

  test "suggest_wiki_completion should require ai_helper module enabled" do
    @project.disable_module!(:ai_helper)

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({ text: "test" })

    assert_response :forbidden
  end

  test "suggest_wiki_completion should require wiki edit permission" do
    Role.find(1).remove_permission!(:edit_wiki_pages)

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({ text: "test" })

    assert_response :forbidden
  end

  test "suggest_wiki_completion with page_name should find wiki page" do
    RedmineAiHelper::Llm.any_instance.stubs(:generate_wiki_completion).returns("page completion")

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: {
           project_id: @project.identifier,
           page_name: @wiki_page.title,
         },
         body: JSON.generate({
           text: "Page content",
           cursor_position: 12,
         })

    assert_response :success
    json = JSON.parse(response.body)
    assert json["suggestion"].is_a?(String)
  end

  test "suggest_wiki_completion should handle LLM errors gracefully" do
    RedmineAiHelper::Llm.any_instance.stubs(:generate_wiki_completion).raises(StandardError.new("Test error"))

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: { project_id: @project.identifier },
         body: JSON.generate({
           text: "Error test",
           cursor_position: 10,
         })

    assert_response :internal_server_error
  end

  test "suggest_wiki_completion should handle section edit correctly" do
    # Mock LLM to capture the parameters passed to it
    captured_params = nil
    RedmineAiHelper::Llm.any_instance.stubs(:generate_wiki_completion) do |*args, **kwargs|
      captured_params = kwargs
      "section completion"
    end

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: {
           project_id: @project.identifier,
           page_name: @wiki_page.title,
         },
         body: JSON.generate({
           text: "Section content",
           cursor_position: 15,
           is_section_edit: true,
         })

    assert_response :success
    json = JSON.parse(response.body)
    assert json["suggestion"].is_a?(String)

    # Verify that is_section_edit was passed correctly to the LLM
    assert_not_nil captured_params
    assert_equal true, captured_params[:is_section_edit]
  end

  test "suggest_wiki_completion should handle full page edit correctly" do
    # Mock LLM to capture the parameters passed to it
    captured_params = nil
    RedmineAiHelper::Llm.any_instance.stubs(:generate_wiki_completion) do |*args, **kwargs|
      captured_params = kwargs
      "full page completion"
    end

    @request.headers["Content-Type"] = "application/json"
    post :suggest_wiki_completion,
         params: {
           project_id: @project.identifier,
           page_name: @wiki_page.title,
         },
         body: JSON.generate({
           text: "Full page content",
           cursor_position: 17,
           is_section_edit: false,
         })

    assert_response :success
    json = JSON.parse(response.body)
    assert json["suggestion"].is_a?(String)

    # Verify that is_section_edit was passed correctly to the LLM
    assert_not_nil captured_params
    assert_equal false, captured_params[:is_section_edit]
  end
end
