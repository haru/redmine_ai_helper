require_relative "../test_helper"

class AiHelperControllerTest < ActionController::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :custom_values, :groups_users, :members, :member_roles, :roles, :user_preferences, :issue_statuses, :wikis, :wiki_pages, :wiki_contents

  context "AiHelperController" do
    setup do
      @controller = AiHelperController.new
      @request = ActionController::TestRequest.create(@controller.class)
      @response = ActionDispatch::TestResponse.create
      @user = User.find(1)
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

      @request.session[:user_id] = @user.id
    end

    context "#chat_form" do
      should "render chat_form partial" do
        get :chat_form, params: { id: @project.id }
        assert_response :success
        assert_template partial: "_chat_form"
      end
    end

    context "#reload" do
      should "render chat partial" do
        get :reload, params: { id: @project.id }
        assert_response :success
        assert_template partial: "_chat"
      end
    end

    context "#chat" do
      should "create a message and render chat partial" do
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        assert_response :success
        assert_template partial: "_chat"
        assert_not_nil assigns(:message)
        assert_equal "Hello AI", assigns(:message).content
      end

      should "call cleanup_old_conversations when saving message" do
        AiHelperConversation.expects(:cleanup_old_conversations).once
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        assert_response :success
      end
    end

    context "#conversation (delete)" do
      should "delete conversation and return ok" do
        delete :conversation, params: { id: @project.id, conversation_id: @conversation.id }
        assert_response :success
        assert_equal "ok", JSON.parse(@response.body)["status"]
      end
    end

    context "#conversation (get)" do
      should "render chat partial" do
        get :conversation, params: { id: @project.id, conversation_id: @conversation.id }
        assert_response :success
        assert_template partial: "_chat"
      end
    end

    context "#history" do
      should "render history partial and assign conversations" do
        get :history, params: { id: @project.id }
        assert_response :success
        assert_template partial: "_history"
        assert_not_nil assigns(:conversations)
      end
    end

    context "#call_llm" do
      should "call LLM and respond successfully" do
        openai_mock = mock("OpenAI::Client")
        openai_mock.stubs(:chat).returns({ "choices" => [{ "text" => "test answer" }] })
        OpenAI::Client.stubs(:new).returns(openai_mock)

        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        assert_response :success
        post :call_llm, params: { id: @project.id, controller_name: "issues", action_name: "show", content_id: 1, additional_info: { key: "value" } }
        assert_response :success
      end

      should "call cleanup_old_conversations when saving conversation" do
        # Mock LLM to avoid actual API calls
        llm_mock = mock("RedmineAiHelper::Llm")
        message_mock = mock("AiHelperMessage")
        llm_mock.stubs(:chat).returns(message_mock)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)
        
        # Expect cleanup to be called
        AiHelperConversation.expects(:cleanup_old_conversations).once
        
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        post :call_llm, params: { id: @project.id, controller_name: "issues", action_name: "show", content_id: 1, additional_info: { key: "value" } }
      end
    end

    context "#clear" do
      should "clear conversation and render chat partial" do
        post :clear, params: { id: @project.id }
        assert_response :success
        assert_template partial: "_chat"
        assert_nil session[:ai_helper][:conversation_id]
      end
    end

    context "#issue_summary" do
      setup do
        @issue = Issue.find(1)
        @llm = RedmineAiHelper::Llm.new
      end

      should "render issue summary partial" do
        get :issue_summary, params: { id: @project.id, issue_id: @issue.id }
        assert_response :success
        assert_template partial: "_issue_summary"
      end

      should "destroy existing summary when update=true" do
        # Create a mock summary
        summary = AiHelperSummaryCache.new(object_class: "Issue", object_id: @issue.id, content: "Test summary")
        summary.stubs(:destroy!).returns(true)
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(summary)
        
        get :issue_summary, params: { id: @project.id, issue_id: @issue.id, update: "true" }
        assert_response :success
        assert_template partial: "_issue_summary"
      end

      should "deny access for non-visible issue" do
        @issue.stubs(:visible?).returns(false)
        summary = @llm.issue_summary(issue: @issue)
        assert_equal "Permission denied", summary
      end
    end

    context "#generate_issue_summary" do
      setup do
        @issue = Issue.find(1)
        @llm = RedmineAiHelper::Llm.new
      end

      should "generate issue summary with streaming" do
        # Mock the LLM response
        RedmineAiHelper::Llm.any_instance.stubs(:issue_summary).returns("Generated summary")
        
        # Mock cache operations
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(nil)
        AiHelperSummaryCache.stubs(:update_issue_cache).with(issue_id: @issue.id, content: "Generated summary").returns(true)
        
        post :generate_issue_summary, params: { id: @issue.id }
        assert_response :success
      end

      should "clear existing cache before generating new summary" do
        # Create mock existing summary
        existing_summary = AiHelperSummaryCache.new(object_class: "Issue", object_id: @issue.id, content: "Old summary")
        existing_summary.stubs(:destroy!).returns(true)
        
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(existing_summary)
        RedmineAiHelper::Llm.any_instance.stubs(:issue_summary).returns("New summary")
        AiHelperSummaryCache.stubs(:update_issue_cache).with(issue_id: @issue.id, content: "New summary").returns(true)
        
        post :generate_issue_summary, params: { id: @issue.id }
        assert_response :success
      end
    end

    context "#generate_issue_reply" do
      setup do
        @issue = Issue.find(1)
        @llm = RedmineAiHelper::Llm.new
      end

      should "deny access for non-visible issue" do
        @issue.stubs(:visible?).returns(false)
        json = { id: @issue.id, instructions: "test instructions" }
        @request.headers["Content-Type"] = "application/json"
        post :generate_issue_reply, params: json

        assert_response :success
      end

      should "generate reply for visible issue" do
        @issue.stubs(:visible?).returns(true)
        json = { id: @issue.id, instructions: "test instructions" }
        @request.headers["Content-Type"] = "application/json"
        post :generate_issue_reply, params: json

        assert_response :success
      end

      should "return Unsupported Media Type for non-JSON request" do
        post :generate_issue_reply, params: { id: @issue.id, instructions: "test instructions" }
        assert_response :unsupported_media_type
      end
    end

    context "#generate_sub_issues" do
      setup do
        @issue = Issue.find_by(project_id: @project.id)
        @llm = RedmineAiHelper::Llm.new
        issue = Issue.new(subject: "Test Issue", project: @project, author: @user)
        @llm.stubs(:generate_sub_issues).returns([issue])
        RedmineAiHelper::Llm.stubs(:new).returns(@llm)
      end

      should "generate sub-issues drafts" do
        json = { id: @issue.id, instructions: "test instructions" }
        @request.headers["Content-Type"] = "application/json"
        post :generate_sub_issues, params: json
        assert_response :success
        assert_template partial: "ai_helper/subissue_gen/_issues"
      end
    end

    context "#add_sub_issues" do
      setup do
        @issue = Issue.new(subject: "Parent Issue", project: @project, author: @user, tracker_id: 1, status_id: 1)
        @issue.save!
        @sub_issue_params = {
          "1" => { subject: "Sub Issue 1", description: "Description 1", tracker_id: 1, check: true, fixed_version_id: nil },
          "2" => { subject: "Sub Issue 2", description: "Description 2", tracker_id: 1, fixed_version_id: nil },
        }
      end

      should "add sub-issues to the current issue" do
        post :add_sub_issues, params: { id: @issue.id, sub_issues: @sub_issue_params, tracker_id: 1 }
        assert_response :redirect
        assert_equal 1, Issue.where(parent_id: @issue.id).count
      end

      should "not add unchecked sub-issues" do
        post :add_sub_issues, params: { id: @issue.id, sub_issues: @sub_issue_params }
        assert_response :redirect
        assert_equal 1, Issue.where(parent_id: @issue.id).count
      end
    end

    context "#wiki_summary" do
      setup do
        @wiki = Wiki.find(1)
        @wiki_page = @wiki.pages.first
        @llm = RedmineAiHelper::Llm.new
      end

      should "render wiki summary content partial" do
        RedmineAiHelper::Llm.any_instance.stubs(:wiki_summary).returns("Test wiki summary")
        
        get :wiki_summary, params: { id: @wiki_page.id }
        assert_response :success
        assert_template partial: "_wiki_summary_content"
      end

      should "create summary when none exists" do
        AiHelperSummaryCache.stubs(:wiki_cache).returns(nil)
        RedmineAiHelper::Llm.any_instance.stubs(:wiki_summary).returns("Generated summary")
        AiHelperSummaryCache.stubs(:update_wiki_cache).returns(
          AiHelperSummaryCache.new(object_class: "WikiPage", object_id: @wiki_page.id, content: "Generated summary")
        )
        
        get :wiki_summary, params: { id: @wiki_page.id }
        assert_response :success
      end

      should "update existing summary when update param is true" do
        existing_summary = AiHelperSummaryCache.new(object_class: "WikiPage", object_id: @wiki_page.id, content: "Old summary")
        AiHelperSummaryCache.stubs(:wiki_cache).returns(existing_summary)
        existing_summary.stubs(:destroy!)
        RedmineAiHelper::Llm.any_instance.stubs(:wiki_summary).returns("New summary")
        AiHelperSummaryCache.stubs(:update_wiki_cache).returns(
          AiHelperSummaryCache.new(object_class: "WikiPage", object_id: @wiki_page.id, content: "New summary")
        )
        
        get :wiki_summary, params: { id: @wiki_page.id, update: "true" }
        assert_response :success
      end

      should "handle 404 for non-existent wiki page" do
        get :wiki_summary, params: { id: 999999 }
        assert_response :not_found
      end
    end

    context "#generate_wiki_summary" do
      setup do
        @wiki = Wiki.find(1)
        @wiki_page = @wiki.pages.first
        @llm = RedmineAiHelper::Llm.new
      end

      should "generate wiki summary with streaming" do
        # Mock the LLM response
        RedmineAiHelper::Llm.any_instance.stubs(:wiki_summary).returns("Generated wiki summary")
        
        # Mock cache operations
        AiHelperSummaryCache.stubs(:wiki_cache).with(wiki_page_id: @wiki_page.id).returns(nil)
        AiHelperSummaryCache.stubs(:update_wiki_cache).with(wiki_page_id: @wiki_page.id, content: "Generated wiki summary").returns(true)
        
        post :generate_wiki_summary, params: { id: @wiki_page.id }
        assert_response :success
      end

      should "clear existing cache before generating new summary" do
        # Create mock existing summary
        existing_summary = AiHelperSummaryCache.new(object_class: "WikiPage", object_id: @wiki_page.id, content: "Old wiki summary")
        existing_summary.stubs(:destroy!).returns(true)
        
        AiHelperSummaryCache.stubs(:wiki_cache).with(wiki_page_id: @wiki_page.id).returns(existing_summary)
        RedmineAiHelper::Llm.any_instance.stubs(:wiki_summary).returns("New wiki summary")
        AiHelperSummaryCache.stubs(:update_wiki_cache).with(wiki_page_id: @wiki_page.id, content: "New wiki summary").returns(true)
        
        post :generate_wiki_summary, params: { id: @wiki_page.id }
        assert_response :success
      end

      should "handle wiki page not found" do
        get :generate_wiki_summary, params: { id: 999999 }
        assert_response :not_found
      end
    end

    context "#generate_issue_reply error handling" do
      setup do
        @issue = Issue.find(1)
      end

      should "return unsupported media type for non-JSON request" do
        post :generate_issue_reply, params: { id: @issue.id, instructions: "test" }
        assert_response :unsupported_media_type
      end
    end

    context "#generate_sub_issues error handling" do
      setup do
        @issue = Issue.find(1)
      end

      should "return unsupported media type for non-JSON request" do
        post :generate_sub_issues, params: { id: @issue.id, instructions: "test" }
        assert_response :unsupported_media_type
      end

    end

    context "#add_sub_issues error handling" do
      setup do
        @issue = Issue.new(subject: "Parent Issue", project: @project, author: @user, tracker_id: 1, status_id: 1)
        @issue.save!
        @sub_issue_params = {
          "1" => { subject: "", description: "Invalid issue", tracker_id: 1, check: true },
        }
      end

      should "handle validation errors when creating sub-issues" do
        # Mock issue save failure
        Issue.any_instance.stubs(:save).returns(false)
        Issue.any_instance.stubs(:errors).returns(mock('errors').tap do |errors|
          errors.stubs(:full_messages).returns(["Subject can't be blank"])
        end)
        
        post :add_sub_issues, params: { id: @issue.id, sub_issues: @sub_issue_params, tracker_id: 1 }
        assert_response :redirect
        assert_not_nil flash[:error]
      end
    end
  end
end
