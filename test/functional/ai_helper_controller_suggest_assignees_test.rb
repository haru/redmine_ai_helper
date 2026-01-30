require_relative "../test_helper"

class AiHelperControllerSuggestAssigneesTest < ActionController::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users,
           :issue_categories, :versions, :custom_fields, :custom_values,
           :groups_users, :members, :member_roles, :roles, :user_preferences,
           :wikis, :wiki_pages, :wiki_contents

  tests AiHelperController

  context "AiHelperController#suggest_assignees" do
    setup do
      @controller = AiHelperController.new
      @request = ActionController::TestRequest.create(@controller.class)
      @response = ActionDispatch::TestResponse.create
      @user = User.find(1) # Admin user
      @project = projects(:projects_001)
      @request.session[:user_id] = @user.id
      @conversation = AiHelperConversation.create(user: @user, title: "Chat with AI")
      message = AiHelperMessage.new(content: "Hello", role: "user")
      @conversation.messages << message
      @conversation.save!

      enabled_module = EnabledModule.new
      enabled_module.project_id = @project.id
      enabled_module.name = "ai_helper"
      enabled_module.save!

      # Stub the suggestion service to avoid actual LLM/vector calls
      @mock_result = {
        history_based: { available: false, suggestions: [] },
        workload_based: {
          available: true,
          suggestions: [
            { user_id: 2, user_name: "John Smith", open_issues_count: 3 },
            { user_id: 3, user_name: "Dave Lopper", open_issues_count: 5 },
          ]
        },
        instruction_based: { available: false, suggestions: [] }
      }
      RedmineAiHelper::AssignmentSuggestion.any_instance.stubs(:suggest).returns(@mock_result)
    end

    context "with valid permissions" do
      should "return HTML response for new issue" do
        @request.headers["Content-Type"] = "application/json"
        post :suggest_assignees, params: { id: @project.id, issue_id: "new" },
             body: { subject: "Test issue", description: "Test description" }.to_json
        assert_response :success
        # Response is now HTML, not JSON
        assert_includes @response.body, "ai-helper-suggest-assignee"
        assert_includes @response.body, "John Smith"
        assert_includes @response.body, "Dave Lopper"
      end

      should "return HTML response for existing issue" do
        issue = issues(:issues_001)
        @request.headers["Content-Type"] = "application/json"
        post :suggest_assignees, params: { id: @project.id, issue_id: issue.id.to_s },
             body: { subject: "Test issue", description: "Test description" }.to_json
        assert_response :success
        # Response is HTML with workload-based suggestions
        assert_includes @response.body, "ai-helper-suggest-assignee"
      end

      should "return error HTML when subject is missing" do
        @request.headers["Content-Type"] = "application/json"
        post :suggest_assignees, params: { id: @project.id, issue_id: "new" },
             body: { description: "Test description" }.to_json
        assert_response :bad_request
        # Response is HTML error, not JSON
        assert_includes @response.body, "ai-helper-suggest-assignee-error"
      end

      should "return error for non-JSON content type" do
        post :suggest_assignees, params: { id: @project.id, issue_id: "new", subject: "Test" }
        assert_response :unsupported_media_type
      end

      should "return error when issue does not belong to the project" do
        other_project_issue = issues(:issues_004) # issue from another project
        if other_project_issue.project_id != @project.id
          @request.headers["Content-Type"] = "application/json"
          post :suggest_assignees, params: { id: @project.id, issue_id: other_project_issue.id.to_s },
               body: { subject: "Test" }.to_json
          assert_response :bad_request
        end
      end

      should "return HTML with close button" do
        @request.headers["Content-Type"] = "application/json"
        post :suggest_assignees, params: { id: @project.id, issue_id: "new" },
             body: { subject: "Test issue" }.to_json
        assert_response :success
        # HTML should contain close button
        assert_includes @response.body, "ai-helper-suggest-assignee-close-btn"
      end
    end

    context "without permissions" do
      setup do
        # Use a user without membership in the project
        @non_member = User.find(4) # Robert Hill
        @request.session[:user_id] = @non_member.id

        # Remove any existing membership for this user in the project
        Member.where(user_id: @non_member.id, project_id: @project.id).destroy_all
      end

      should "return 403 forbidden" do
        @request.headers["Content-Type"] = "application/json"
        post :suggest_assignees, params: { id: @project.id, issue_id: "new" },
             body: { subject: "Test issue" }.to_json
        assert_response 403
      end
    end
  end
end
