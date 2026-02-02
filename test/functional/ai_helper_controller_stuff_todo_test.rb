require_relative "../test_helper"

class AiHelperControllerStuffTodoTest < ActionController::TestCase
  fixtures :projects, :users, :issues, :issue_statuses, :trackers, :enumerations, :members, :member_roles, :roles

  context "GET stuff_todo" do
    setup do
      @controller = AiHelperController.new
      @request = ActionController::TestRequest.create(@controller.class)
      @response = ActionDispatch::TestResponse.create
      @user = User.find(1) # Use admin user
      @project = projects(:projects_001)
      @request.session[:user_id] = @user.id
      User.current = @user

      # Enable ai_helper module for the project
      enabled_module = EnabledModule.new
      enabled_module.project_id = @project.id
      enabled_module.name = "ai_helper"
      enabled_module.save!
    end

    should "return 403 without permission" do
      # Use a user without permission
      user_no_perm = User.find(4)
      @request.session[:user_id] = user_no_perm.id

      get :stuff_todo, params: { id: @project.identifier }

      assert_response 403
    end

    should "return SSE streaming response with markdown content" do
      # Mock Llm to avoid actual LLM calls
      llm_mock = mock("RedmineAiHelper::Llm")
      llm_mock.expects(:stuff_todo).with(
        project: @project,
        stream_proc: instance_of(Proc)
      ).returns("## Suggested tasks")

      RedmineAiHelper::Llm.expects(:new).returns(llm_mock)

      get :stuff_todo, params: { id: @project.identifier }

      assert_response :success
    end

    should "set correct streaming headers" do
      # Mock Llm
      llm_mock = mock("RedmineAiHelper::Llm")
      llm_mock.stubs(:stuff_todo).returns("## Suggested tasks")
      RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

      get :stuff_todo, params: { id: @project.identifier }

      # Check streaming headers
      assert_equal "text/event-stream", @response.headers["Content-Type"]
      assert_equal "no-cache", @response.headers["Cache-Control"]
    end

    should "call Llm#stuff_todo with project parameter" do
      # Mock Llm
      llm_mock = mock("RedmineAiHelper::Llm")
      llm_mock.expects(:stuff_todo).with(
        project: @project,
        stream_proc: instance_of(Proc)
      ).returns("## Suggested tasks")

      RedmineAiHelper::Llm.expects(:new).returns(llm_mock)

      get :stuff_todo, params: { id: @project.identifier }

      assert_response :success
    end
  end
end
