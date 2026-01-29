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
        assert_template partial: "ai_helper/chat/_chat_form"
      end
    end

    context "#reload" do
      should "render chat partial" do
        get :reload, params: { id: @project.id }
        assert_response :success
        assert_template partial: "ai_helper/chat/_chat"
      end
    end

    context "#chat" do
      should "create a message and render chat partial" do
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        assert_response :success
        assert_template partial: "ai_helper/chat/_chat"
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
        assert_template partial: "ai_helper/chat/_chat"
      end
    end

    context "#history" do
      should "render history partial and assign conversations" do
        get :history, params: { id: @project.id }
        assert_response :success
        assert_template partial: "ai_helper/chat/_history"
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

      should "handle nil additional_info parameter" do
        # Mock conversation to avoid LLM calls
        @controller.stubs(:find_conversation)
        @conversation.stubs(:messages).returns(mock('messages').tap { |m| m.stubs(:<<) })
        @conversation.stubs(:save!)
        AiHelperConversation.stubs(:cleanup_old_conversations)

        # Mock LLM
        llm_mock = mock("RedmineAiHelper::Llm")
        message_mock = mock("AiHelperMessage")
        llm_mock.stubs(:chat).returns(message_mock)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        assert_raises(NoMethodError) do
          post :call_llm, params: { id: @project.id, controller_name: "issues", action_name: "show" }
        end
      end
    end

    context "#clear" do
      should "clear conversation and render chat partial" do
        post :clear, params: { id: @project.id }
        assert_response :success
        assert_template partial: "ai_helper/chat/_chat"
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
        assert_template partial: "ai_helper/issues/_summary"
      end

      should "destroy existing summary when update=true" do
        # Create a mock summary
        summary = AiHelperSummaryCache.new(object_class: "Issue", object_id: @issue.id, content: "Test summary")
        summary.stubs(:destroy!).returns(true)
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(summary)

        get :issue_summary, params: { id: @project.id, issue_id: @issue.id, update: "true" }
        assert_response :success
        assert_template partial: "ai_helper/issues/_summary"
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
        assert_template partial: "ai_helper/issues/subissues/_issues"
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
        assert_template partial: "ai_helper/wiki/_summary_content"
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

    context "#similar_issues" do
      setup do
        @issue = Issue.find(1)
        @issue.project = @project
        @issue.save!
        @llm_mock = mock("RedmineAiHelper::Llm")
        RedmineAiHelper::Llm.stubs(:new).returns(@llm_mock)
      end

      should "return similar issues successfully" do
        # Mock LLM find_similar_issues method with proper structure
        similar_issues = [{
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }
        assert_response :success

        # Check that the response contains the expected content (HTML partial)
        assert_match /Similar issue/, @response.body
        assert_match /85\.0%/, @response.body
        assert_match /Updated/, @response.body
      end

      should "exclude current issue from results" do
        # Mock LLM find_similar_issues method (should already exclude current issue)
        similar_issues = [{
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }
        assert_response :success

        # Check that only the other issue is included (current issue excluded)
        assert_match /Similar issue/, @response.body
        # Check that only issue ID 2 is present, not the current issue ID 1
        assert_match />2</, @response.body
        assert_no_match />#{@issue.id}</, @response.body
      end

      should "return empty array when no similar issues found" do
        # Mock LLM find_similar_issues method returning empty array
        @llm_mock.stubs(:find_similar_issues).with(issue: @issue).returns([])

        get :similar_issues, params: { id: @issue.id }
        assert_response :success

        # Check that no similar issues message is displayed
        assert_match /No similar issues found/, @response.body
      end

      should "handle vector search errors gracefully" do
        # Mock LLM find_similar_issues method raising an error
        @llm_mock.stubs(:find_similar_issues).with(issue: @issue).raises(StandardError.new("Vector search failed"))

        get :similar_issues, params: { id: @issue.id }
        assert_response :internal_server_error

        response_data = JSON.parse(@response.body)
        assert_equal "Vector search failed", response_data["error"]
      end

      should "handle missing assigned_to_name gracefully" do
        # Mock LLM find_similar_issues method with nil assigned_to
        similar_issues = [{
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.now,
          assigned_to: nil,
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }
        assert_response :success

        # Check that the similar issue is displayed even without assigned_to_name
        assert_match /Similar issue/, @response.body
        assert_match /85\.0%/, @response.body
      end
    end

    context "#project_health" do
      should "render project health partial" do
        # Mock cache to return health report
        Rails.cache.stubs(:fetch).returns("Test health report content")

        get :project_health, params: { id: @project.id }
        assert_response :success
        assert_template partial: "ai_helper/project/_health_report"
        assert_not_nil assigns(:health_report)
      end

      should "generate PDF when format is pdf and health report exists" do
        # Mock cache to return health report
        Rails.cache.stubs(:fetch).returns("Test health report content")

        # Mock PDF generation
        @controller.stubs(:project_health_to_pdf).returns("PDF content")

        get :project_health, params: { id: @project.id, format: :pdf }
        assert_response :success
        assert_equal "application/pdf", @response.content_type
      end

      should "redirect when no health report available for PDF" do
        # Mock cache to return error hash
        Rails.cache.stubs(:fetch).returns({ error: "No data" })

        get :project_health, params: { id: @project.id, format: :pdf }
        assert_response :redirect
      end

    end

    context "#project_health_metadata" do
      should "return latest report metadata without regeneration" do
        AiHelperHealthReport.delete_all
        report = AiHelperHealthReport.create!(
          project: @project,
          user: @user,
          health_report: "Persisted report content"
        )

        @controller.expects(:generate_project_health_report).never

        get :project_health_metadata, params: { id: @project.id }
        assert_response :success

        response_body = JSON.parse(@response.body)
        assert_equal report.id, response_body["id"]
        assert_equal report.created_at.iso8601, response_body["created_at_iso8601"]
        assert_equal @controller.view_context.format_time(report.created_at), response_body["created_on_formatted"]
      end

      should "return no content when no report exists" do
        AiHelperHealthReport.delete_all

        get :project_health_metadata, params: { id: @project.id }
        assert_response :no_content
      end
    end

    context "#project_health_pdf" do
      should "generate PDF from health report content" do
        health_content = "# Test Health Report\n\nThis is a test report."

        # Mock PDF generation
        @controller.stubs(:project_health_to_pdf).returns("PDF content")

        post :project_health_pdf, params: { id: @project.id, health_report_content: health_content }
        assert_response :success
        assert_equal "application/pdf", @response.content_type
        assert_match /#{@project.identifier}-health-report-/, @response.headers['Content-Disposition']
      end

      should "sanitize malicious content" do
        malicious_content = "<script>alert('xss')</script># Test Report\n<div>Content</div>"
        expected_sanitized = "# Test Report\nContent"

        # Mock PDF generation and verify sanitized content is passed
        @controller.expects(:project_health_to_pdf).with(@project, expected_sanitized).returns("PDF content")

        post :project_health_pdf, params: { id: @project.id, health_report_content: malicious_content }
        assert_response :success
      end

      should "redirect when no content provided" do
        post :project_health_pdf, params: { id: @project.id, health_report_content: "" }
        assert_response :redirect
      end

      should "redirect when content is nil" do
        post :project_health_pdf, params: { id: @project.id }
        assert_response :redirect
      end
    end

    context "#generate_project_health" do
      should "generate project health report with streaming" do
        # Mock LLM and response
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:project_health_report).returns("Generated health report")
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        # Mock cache operations
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }
        assert_response :success
        assert_not_nil @response.body
      end

      should "handle LLM errors gracefully" do
        get :generate_project_health, params: { id: @project.id }
        assert_response :success
        assert_match /data:/, @response.body
      end
    end

    context "private methods and error handling" do
      should "handle find_user method" do
        # This tests the private method indirectly through chat
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Test message" } }
        assert_response :success
      end

      should "handle conversation creation and management" do
        # Test conversation creation and session management
        post :chat, params: { id: @project.id, ai_helper_message: { content: "First message" } }
        assert_response :success

        # Verify conversation ID is set in session
        assert_not_nil session[:ai_helper][:conversation_id]

        # Test loading existing conversation
        get :history, params: { id: @project.id }
        assert_response :success
      end

      should "handle find_wiki_page method through wiki_summary" do
        wiki = Wiki.find(1)
        wiki_page = wiki.pages.first

        get :wiki_summary, params: { id: wiki_page.id }
        assert_response :success
      end

      should "handle non-existent wiki page" do
        get :wiki_summary, params: { id: 999999 }
        assert_response :not_found
      end

      should "handle project health authorization" do
        # Test with user who has permission
        get :project_health, params: { id: @project.id }
        assert_response :success
      end

      should "handle streaming response chunks" do
        # Test streaming functionality through generate_project_health
        get :generate_project_health, params: { id: @project.id }
        assert_response :success

        # Should be a streaming response
        assert_equal "text/event-stream", @response.content_type
      end

      should "handle conversation cleanup" do
        # Create a conversation and test cleanup
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Test" } }
        conversation_id = session[:ai_helper][:conversation_id]

        # Verify conversation exists
        assert AiHelperConversation.exists?(conversation_id)

        # Test conversation deletion
        delete :conversation, params: { id: @project.id, conversation_id: conversation_id }
        assert_response :success

        # Verify conversation was deleted
        assert_not AiHelperConversation.exists?(conversation_id)
      end

      should "handle missing conversation for deletion" do
        assert_raises(ActiveRecord::RecordNotFound) do
          delete :conversation, params: { id: @project.id, conversation_id: 999999 }
        end
      end

      should "handle call_llm with missing parameters" do
        assert_raises(NoMethodError) do
          post :call_llm, params: { id: @project.id }
        end
      end

      should "handle call_llm with complete parameters" do
        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { test: "data" }
        }
        assert_response :success
      end

      should "handle generate_wiki_summary for non-existent page" do
        post :generate_wiki_summary, params: { id: 999999 }
        assert_response :not_found
      end

      should "handle project_health with caching" do
        # First request should generate and cache
        get :project_health, params: {
          id: @project.id,
          version_id: 1,
          start_date: "2025-01-01",
          end_date: "2025-12-31"
        }
        assert_response :success

        # Second request should use cache
        get :project_health, params: {
          id: @project.id,
          version_id: 1,
          start_date: "2025-01-01",
          end_date: "2025-12-31"
        }
        assert_response :success
      end

      should "handle project_health_pdf with malformed content" do
        malicious_content = "<script>alert('xss')</script>Valid content"

        post :project_health_pdf, params: {
          id: @project.id,
          health_report_content: malicious_content
        }
        assert_response :success
        assert_equal "application/pdf", @response.content_type
      end

      should "handle project_health_pdf with very long content" do
        long_content = "A" * 10000 # Very long content

        post :project_health_pdf, params: {
          id: @project.id,
          health_report_content: long_content
        }
        assert_response :success
        assert_equal "application/pdf", @response.content_type
      end

      should "handle generate_project_health with parameters" do
        get :generate_project_health, params: {
          id: @project.id,
          version_id: 1,
          start_date: "2025-01-01",
          end_date: "2025-12-31"
        }
        assert_response :success
        assert_match /data:/, @response.body
      end

      should "handle chat with empty message" do
        assert_raises(ActiveRecord::RecordInvalid) do
          post :chat, params: { id: @project.id, ai_helper_message: { content: "" } }
        end
      end

      should "handle chat without ai_helper_message parameter" do
        assert_raises(NoMethodError) do
          post :chat, params: { id: @project.id }
        end
      end

      should "handle multiple chat messages in sequence" do
        # First message
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello" } }
        assert_response :success
        conversation_id = session[:ai_helper][:conversation_id]

        # Second message in same conversation
        post :chat, params: { id: @project.id, ai_helper_message: { content: "World" } }
        assert_response :success
        assert_equal conversation_id, session[:ai_helper][:conversation_id]
      end

      should "handle session management across requests" do
        # Clear session first
        post :clear, params: { id: @project.id }
        assert_response :success
        assert_nil session[:ai_helper][:conversation_id]

        # Start new conversation
        post :chat, params: { id: @project.id, ai_helper_message: { content: "New conversation" } }
        assert_response :success
        assert_not_nil session[:ai_helper][:conversation_id]
      end

      should "handle reload with existing conversation" do
        # Create conversation first
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Test" } }
        conversation_id = session[:ai_helper][:conversation_id]

        # Test reload
        get :reload, params: { id: @project.id }
        assert_response :success
        assert_template partial: "ai_helper/chat/_chat"
      end

      should "handle conversation switching" do
        # Create first conversation
        post :chat, params: { id: @project.id, ai_helper_message: { content: "First" } }
        first_conversation_id = session[:ai_helper][:conversation_id]

        # Create second conversation (clear and create new)
        post :clear, params: { id: @project.id }
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Second" } }
        second_conversation_id = session[:ai_helper][:conversation_id]

        assert_not_equal first_conversation_id, second_conversation_id

        # Switch back to first conversation
        get :conversation, params: { id: @project.id, conversation_id: first_conversation_id }
        assert_response :success
        assert_equal first_conversation_id, session[:ai_helper][:conversation_id]
      end

      should "handle error in issue_summary update" do
        issue = Issue.find(1)

        # Mock to simulate cache destruction error
        AiHelperSummaryCache.stubs(:issue_cache).returns(nil)

        get :issue_summary, params: { id: @project.id, issue_id: issue.id, update: "true" }
        assert_response :success
      end

      should "handle error in wiki_summary update" do
        wiki = Wiki.find(1)
        wiki_page = wiki.pages.first

        # Mock to simulate cache destruction error
        AiHelperSummaryCache.stubs(:wiki_cache).returns(nil)

        get :wiki_summary, params: { id: wiki_page.id, update: "true" }
        assert_response :success
      end



      should "handle authorization failure in authorize_project_health" do
        # Create project without AI helper module
        project = Project.create!(name: "Test Project", identifier: "test-project-no-ai")
        User.current.stubs(:allowed_to?).returns(false)

        get :project_health, params: { id: project.id }
        assert_response :forbidden
      end

      should "handle project visibility check in authorize_project_health" do
        project = Project.create!(name: "Hidden Project", identifier: "hidden-project")
        project.stubs(:visible?).returns(false)

        get :project_health, params: { id: project.id }
        assert_response :forbidden
      end

      should "handle streaming response errors in generate_project_health" do
        # Mock the error condition that triggers lines 328-351
        error = StandardError.new("LLM Error")
        error.set_backtrace(["line1", "line2", "line3"])

        # Mock to avoid actual LLM calls but still trigger error path
        llm_mock = mock('llm')
        llm_mock.stubs(:project_health_report).raises(error)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        get :generate_project_health, params: { id: @project.id }
        assert_response :success

        # Check that streaming response started (initial chunk)
        assert_match /chatcmpl-/, @response.body
        assert_equal "text/event-stream", @response.content_type
      end

      should "handle find_conversation when conversation exists but is invalid" do
        # Set invalid conversation ID in session
        session[:ai_helper] = { conversation_id: 999999 }

        get :chat_form, params: { id: @project.id }
        assert_response :success

        # Should create new conversation when existing one not found
        assert_not_nil assigns(:message)
      end

      should "handle cache_proc in generate_issue_summary" do
        issue = Issue.find(1)

        # Mock LLM to test the cache_proc
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:issue_summary).with(issue: issue, stream_proc: anything).returns("Summary content")
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        # Mock cache operations
        AiHelperSummaryCache.stubs(:issue_cache).returns(nil)
        AiHelperSummaryCache.stubs(:update_issue_cache).returns(true)

        post :generate_issue_summary, params: { id: issue.id }
        assert_response :success
      end

      should "handle cache_proc in generate_wiki_summary" do
        wiki = Wiki.find(1)
        wiki_page = wiki.pages.first

        # Mock LLM to test the cache_proc
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:wiki_summary).with(wiki_page: wiki_page, stream_proc: anything).returns("Wiki summary content")
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        # Mock cache operations
        AiHelperSummaryCache.stubs(:wiki_cache).returns(nil)
        AiHelperSummaryCache.stubs(:update_wiki_cache).returns(true)

        post :generate_wiki_summary, params: { id: wiki_page.id }
        assert_response :success
      end

      should "handle content_id parameter conversion in call_llm" do
        # Test when content_id is blank
        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: "",
          additional_info: { test: "data" }
        }
        assert_response :success
      end

      should "handle fixed_version_id assignment in add_sub_issues" do
        parent_issue = Issue.new(subject: "Parent Issue", project: @project, author: @user, tracker_id: 1, status_id: 1)
        parent_issue.save!

        sub_issue_params = {
          "1" => { subject: "Sub Issue", description: "Description", tracker_id: 1, check: true, fixed_version_id: "" },
        }

        post :add_sub_issues, params: { id: parent_issue.id, sub_issues: sub_issue_params, tracker_id: 1 }
        assert_response :redirect
      end

      should "handle basic stream_llm_response functionality" do
        # Test the basic streaming functionality
        get :generate_project_health, params: { id: @project.id }
        assert_response :success
        assert_equal "text/event-stream", @response.content_type
      end

      should "handle project_health basic functionality" do
        # Test basic project_health functionality
        get :project_health, params: { id: @project.id }
        assert_response :success
        assert_not_nil assigns(:health_report)
      end

      should "handle write_chunk functionality" do
        # Test the write_chunk private method indirectly
        get :generate_project_health, params: { id: @project.id }
        assert_response :success
        # The write_chunk method is used internally during streaming
        assert_match /data:/, @response.body
      end

      should "handle project health with nil health report" do
        # Test when health report generation returns nil
        @controller.stubs(:generate_project_health_report).returns(nil)

        get :project_health, params: { id: @project.id, format: :pdf }
        assert_response :redirect
      end

      should "handle find_wiki_page with valid page" do
        wiki = Wiki.find(1)
        wiki_page = wiki.pages.first

        get :wiki_summary, params: { id: wiki_page.id }
        assert_response :success
        assert_equal wiki_page, assigns(:wiki_page)
        assert_equal wiki_page.wiki.project, assigns(:project)
      end

      should "handle conversation_id method" do
        # Test conversation_id private method
        session[:ai_helper] = { conversation_id: 123 }

        get :chat_form, params: { id: @project.id }
        assert_response :success
        # The conversation_id method is used internally
      end

      should "handle set_conversation_id method" do
        # Test set_conversation_id private method
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Test" } }
        assert_response :success
        assert_not_nil session[:ai_helper][:conversation_id]
      end

      should "handle authorize_project_health with valid permissions" do
        # Test successful authorization
        User.current.stubs(:allowed_to?).with(:view_ai_helper, @project).returns(true)
        @project.stubs(:visible?).returns(true)

        get :project_health, params: { id: @project.id }
        assert_response :success
      end

      should "handle cache key generation in project_health" do
        # Test cache key generation with different parameters
        get :project_health, params: {
          id: @project.id,
          version_id: "1",
          start_date: "2025-01-01",
          end_date: "2025-12-31"
        }
        assert_response :success
      end

      should "handle Rails cache operations in generate_project_health" do
        # Test cache delete and write operations
        cache_key = "project_health_#{@project.id}"
        Rails.cache.expects(:delete).with(cache_key)
        Rails.cache.expects(:write).with(cache_key, anything, expires_in: 1.hour)

        get :generate_project_health, params: { id: @project.id }
        assert_response :success
      end

      should "handle typo in controller name parameter" do
        # Test the 'contoller_name' typo in the controller
        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { test: "data" }
        }
        assert_response :success
      end

      should "handle project health PDF with missing report" do
        # Mock cache to return error hash
        Rails.cache.stubs(:fetch).returns({ error: "No data available" })

        get :project_health, params: { id: @project.id, format: :pdf }
        assert_response :redirect
      end

      should "handle conversation reload when need_reload is true" do
        # Create conversation and test deletion with reload
        conversation = AiHelperConversation.create(user: @user, title: "Test conversation")
        session[:ai_helper] = { conversation_id: conversation.id }

        delete :conversation, params: { id: @project.id, conversation_id: conversation.id }
        assert_response :success

        response_data = JSON.parse(@response.body)
        assert_equal "ok", response_data["status"]
        assert_equal true, response_data["reload"]
      end

      should "handle conversation reload when need_reload is false" do
        # Create different conversation to test when need_reload is false
        current_conversation = AiHelperConversation.create(user: @user, title: "Current conversation")
        other_conversation = AiHelperConversation.create(user: @user, title: "Other conversation")
        session[:ai_helper] = { conversation_id: current_conversation.id }

        delete :conversation, params: { id: @project.id, conversation_id: other_conversation.id }
        assert_response :success

        response_data = JSON.parse(@response.body)
        assert_equal "ok", response_data["status"]
        assert_equal false, response_data["reload"]
      end

      should "handle stream_llm_response response_id generation" do
        # Test response ID generation in stream_llm_response
        SecureRandom.stubs(:hex).with(12).returns("test123456789abc")

        get :generate_project_health, params: { id: @project.id }
        assert_response :success
        assert_match /chatcmpl-test123456789abc/, @response.body
      end

      should "handle conversation find_by in find_conversation" do
        # Test when conversation exists but is found by find_by
        existing_conversation = AiHelperConversation.create(user: @user, title: "Existing")
        session[:ai_helper] = { conversation_id: existing_conversation.id }

        get :chat_form, params: { id: @project.id }
        assert_response :success
        assert_equal existing_conversation, assigns(:conversation)
      end

      should "handle project_health cache fetch" do
        # Test cache fetch in project_health method
        cached_content = "Cached health report"
        cache_key = "project_health_#{@project.id}___"
        Rails.cache.stubs(:fetch).with(cache_key, expires_in: 1.hour).returns(cached_content)

        get :project_health, params: { id: @project.id }
        assert_response :success
        assert_equal cached_content, assigns(:health_report)
      end

      # Auto-completion tests
      should "suggest completion with valid request" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns("This is a suggested completion.")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error", cursor_position: 16 }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert json_response.key?('suggestion')
        assert_equal "This is a suggested completion.", json_response['suggestion']
      end

      should "return error for non-JSON request in suggest_completion" do
        issue = Issue.find(1)

        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id, text: "Some text" }

        assert_response :unsupported_media_type
        json_response = JSON.parse(response.body)
        assert_equal "Unsupported Media Type", json_response['error']
      end


      should "return error for empty text in suggest_completion" do
        issue = Issue.find(1)

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "", cursor_position: 0 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)
        assert_equal "Text is required", json_response['error']
      end

      should "return error for text too long in suggest_completion" do
        issue = Issue.find(1)
        long_text = "a" * 5001

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: long_text, cursor_position: 100 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)
        assert_equal "Text too long", json_response['error']
      end

      should "return error for invalid cursor position in suggest_completion" do
        issue = Issue.find(1)
        text = "Test text"

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: text, cursor_position: text.length + 1 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)
        assert_equal "Invalid cursor position", json_response['error']
      end

      should "handle LLM error gracefully in suggest_completion" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).raises(StandardError, "LLM error")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error", cursor_position: 16 }.to_json

        assert_response :internal_server_error
        json_response = JSON.parse(response.body)
        assert_equal "Failed to generate suggestion", json_response['error']
      end

      should "handle suggest_completion with nil cursor position" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns("completion text")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert json_response.key?('suggestion')
        assert_equal "completion text", json_response['suggestion']
      end

      should "suggest completion for notes context type" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns("I have reviewed this issue.")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "I have reviewed", cursor_position: 15, context_type: "note" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert json_response.key?('suggestion')
        assert_equal "I have reviewed this issue.", json_response['suggestion']
      end

      should "return error for invalid context_type" do
        issue = Issue.find(1)

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Test text", cursor_position: 5, context_type: "invalid" }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)
        assert_equal "Invalid context_type. Must be 'description' or 'note'", json_response['error']
      end

      should "return error for note context_type without existing issue" do
        issue = Issue.find(1)
        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: 'new' },
             body: { text: "Test note", cursor_position: 5, context_type: "note" }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)
        assert_equal "Issue is required for note completion", json_response['error']
      end

      should "handle note completion with issue context" do
        issue = Issue.find(1)

        # Create a journal entry for context
        journal = Journal.create!(
          journalized: issue,
          user: User.find(1),
          notes: "This is a test note for context."
        )

        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns(" and I agree with the analysis.")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Thank you for the feedback", cursor_position: 25, context_type: "note" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert json_response.key?('suggestion')
        assert_equal " and I agree with the analysis.", json_response['suggestion']

        # Clean up
        journal.destroy
      end

      # Integration tests for refactored architecture
      should "test refactored generate_text_completion integration" do
        issue = Issue.find(1)

        # Test that the new architecture works end-to-end
        # The controller should call llm.rb which delegates to IssueAgent
        @request.headers["Content-Type"] = "application/json"

        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "This is a test issue", cursor_position: 17, context_type: "description" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert json_response.key?('suggestion')
        # The response should be a string (empty in test environment due to mocking)
        assert json_response['suggestion'].is_a?(String)
      end

      should "test prompt loader integration through agent" do
        issue = Issue.find(1)

        # Mock the PromptLoader to verify it's being used
        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("Mocked prompt text")

        # The IssueAgent should use PromptLoader via load_prompt
        RedmineAiHelper::Agents::IssueAgent.any_instance.expects(:load_prompt)
          .with("issue_agent/inline_completion")
          .returns(mock_prompt)

        RedmineAiHelper::Agents::IssueAgent.any_instance.stubs(:chat).returns("Mocked completion")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Test prompt loading", cursor_position: 4, context_type: "description" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal "Mocked completion", json_response['suggestion']
      end

      should "test note context integration" do
        issue = Issue.find(1)

        # Create test journal for context
        journal = Journal.create!(
          journalized: issue,
          user: User.find(1),
          notes: "Previous discussion point"
        )

        # Mock the note template loading
        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("Note completion prompt")

        RedmineAiHelper::Agents::IssueAgent.any_instance.expects(:load_prompt)
          .with("issue_agent/note_inline_completion")
          .returns(mock_prompt)

        RedmineAiHelper::Agents::IssueAgent.any_instance.stubs(:chat).returns("Contextual note completion")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "I agree with", cursor_position: 12, context_type: "note" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)
        assert_equal "Contextual note completion", json_response['suggestion']

        # Clean up
        journal.destroy
      end
    end

    context "#check_duplicates" do
      setup do
        @llm_mock = mock("RedmineAiHelper::Llm")
        RedmineAiHelper::Llm.stubs(:new).returns(@llm_mock)
      end

      should "return similar issues successfully" do
        similar_issues = [{
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "Test subject", description: "Test description", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Test subject", description: "Test description" }.to_json

        assert_response :success
        assert_match /Similar issue/, @response.body
        assert_match /85\.0%/, @response.body
      end

      should "return error when content type is not JSON" do
        post :check_duplicates, params: { id: @project.id }

        assert_response :unsupported_media_type
        response_data = JSON.parse(@response.body)
        assert_equal "Unsupported Media Type", response_data["error"]
      end

      should "return error when subject and description are empty" do
        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "", description: "" }.to_json

        assert_response :bad_request
        response_data = JSON.parse(@response.body)
        assert response_data["error"].present?
      end

      should "return empty result when no similar issues found" do
        @llm_mock.stubs(:find_similar_issues_by_content).returns([])

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Unique subject", description: "Unique description" }.to_json

        assert_response :success
        assert_match /No similar issues found|類似するチケットが見つかりませんでした/, @response.body
      end

      should "handle vector search errors gracefully" do
        @llm_mock.stubs(:find_similar_issues_by_content)
                 .raises(StandardError.new("Vector search failed"))

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Test", description: "Test" }.to_json

        assert_response :internal_server_error
        response_data = JSON.parse(@response.body)
        assert_equal "Vector search failed", response_data["error"]
      end

      should "work with only subject provided" do
        similar_issues = [{
          id: 3,
          project: { name: "Test Project" },
          subject: "Matching issue",
          status: { name: "New" },
          updated_on: Time.now,
          assigned_to: nil,
          similarity_score: 72.0,
          issue_url: "/issues/3"
        }]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "Test subject", description: "", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Test subject", description: "" }.to_json

        assert_response :success
        assert_match /Matching issue/, @response.body
      end

      should "work with only description provided" do
        similar_issues = [{
          id: 4,
          project: { name: "Test Project" },
          subject: "Another matching issue",
          status: { name: "In Progress" },
          updated_on: Time.now,
          assigned_to: { name: "Developer" },
          similarity_score: 68.5,
          issue_url: "/issues/4"
        }]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "", description: "Test description", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "", description: "Test description" }.to_json

        assert_response :success
        assert_match /Another matching issue/, @response.body
      end
    end


  end
end
