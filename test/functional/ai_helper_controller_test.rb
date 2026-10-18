require_relative "../test_helper"

class AiHelperControllerTest < ActionController::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :custom_values, :groups_users, :members, :member_roles, :roles, :user_preferences, :issue_statuses, :wikis, :wiki_pages, :wiki_contents

  # Inflate the Flate streams of a PDF and return their text content.
  def pdf_text(pdf)
    pdf.b.scan(/stream\r?\n(.*?)endstream/m).map do |(data)|
      Zlib::Inflate.inflate(data)
    rescue Zlib::Error
      data
    end.join.delete("\x00").gsub(/\\([()])/, '\1')
  end

  # Add an assistant answer with the given web search sources to the conversation.
  def add_answer(citations)
    message = AiHelperMessage.new(content: "The answer", role: "assistant")
    message.web_citations = citations
    @conversation.messages << message
    @conversation.save!
  end

  def citation(url, title = nil)
    RedmineAiHelper::WebCitation.new(url: url, title: title)
  end

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

      should "not render a read-only mode notice in the chat form when read_only_mode is enabled" do
        AiHelperSetting.stubs(:read_only_mode?).returns(true)

        get :chat_form, params: { id: @project.id }

        assert_response :success
        assert_select "#ai_helper_chat_form .icon-lock", count: 0
      end
    end

    context "_interactive_options partial" do
      should "render a free-input button with data-free-input attribute" do
        get :chat_form, params: { id: @project.id }
        html = @controller.render_to_string(partial: "ai_helper/chat/interactive_options")

        assert_match(/data-free-input="true"/, html)
      end

      should "render free-input button with correct English label text" do
        get :chat_form, params: { id: @project.id }
        I18n.with_locale(:en) do
          html = @controller.render_to_string(partial: "ai_helper/chat/interactive_options")

          assert_match(/#{Regexp.escape(I18n.t('label_ai_helper_free_input_option', locale: :en))}/, html)
        end
      end

      context "with Japanese locale" do
        should "render free-input button with Japanese label" do
          get :chat_form, params: { id: @project.id }
          I18n.with_locale(:ja) do
            html = @controller.render_to_string(partial: "ai_helper/chat/interactive_options")

            assert_match(/#{Regexp.escape(I18n.t('label_ai_helper_free_input_option', locale: :ja))}/, html)
          end
        end
      end
    end

    context "#reload" do
      should "render chat partial" do
        get :reload, params: { id: @project.id }

        assert_response :success
        assert_template partial: "ai_helper/chat/_chat"
      end
    end

    context "#reload with citations" do
      setup do
        @request.session[:ai_helper] = { conversation_id: @conversation.id }
      end

      should "show a heading and a list of sources under the answer" do
        add_answer([ citation("https://example.com/a", "Page A"), citation("https://example.com/b") ])

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations strong", text: I18n.t(:label_ai_helper_citations)
        assert_select "div.aihelper-citations ol li", count: 2
        assert_select "div.aihelper-citations li:nth-child(1) a[href='https://example.com/a']", text: "Page A"
        assert_select "div.aihelper-citations li:nth-child(2) a[href='https://example.com/b']", text: "https://example.com/b"
      end

      should "open links in a new tab without leaking the opener" do
        add_answer([ citation("https://example.com/a", "Page A") ])

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations a[target='_blank'][rel='noopener noreferrer']"
      end

      should "show a non http(s) source as text, not as a link" do
        add_answer([ citation("javascript:alert(1)", "Evil") ])

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations a", count: 0
        assert_select "div.aihelper-citations li", text: /Evil/
        assert_select "div.aihelper-citations li", text: /javascript:alert\(1\)/
      end

      should "escape HTML in the title and the url" do
        add_answer([ citation("https://example.com/?a=<b>&c=\"d\"", "<script>alert(1)</script>") ])

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations script", count: 0
        assert_includes response.body, "&lt;script&gt;alert(1)&lt;/script&gt;"
      end

      should "show neither heading nor list for an answer without sources" do
        add_answer([])

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations", count: 0
        doc = Nokogiri::HTML(response.body)
        doc.css("script").remove
        assert_not_includes doc.text, I18n.t(:label_ai_helper_citations)
      end

      should "show the heading in Japanese" do
        add_answer([ citation("https://example.com/a") ])
        @user.update_column(:language, "ja")

        get :reload, params: { id: @project.id }

        assert_select "div.aihelper-citations strong", text: I18n.t(:label_ai_helper_citations, locale: :ja)
        assert_equal "出典", I18n.t(:label_ai_helper_citations, locale: :ja)
      end
    end

    context "#call_llm with citations" do
      should "save the answer with its web search sources" do
        answer = AiHelperMessage.new(content: "The answer", role: "assistant")
        answer.web_citations = [ citation("https://example.com/a", "Page A"), citation("https://example.com/b") ]
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:chat).returns(answer)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }
        post :call_llm, params: { id: @project.id, controller_name: "issues", action_name: "show", content_id: 1, additional_info: { key: "value" } }

        saved = AiHelperMessage.where(role: "assistant").order(:id).last.reload
        assert_equal "The answer", saved.content
        assert_equal [ citation("https://example.com/a", "Page A"), citation("https://example.com/b") ], saved.web_citations
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

      should "label messages imported from a chat channel" do
        @conversation.messages << AiHelperMessage.new(role: "context", content: "Yamada: it crashes on save")
        @conversation.save!

        get :conversation, params: { id: @project.id, conversation_id: @conversation.id }

        assert_response :success
        assert_select "pre", text: "Yamada: it crashes on save"
        assert_match(/#{Regexp.escape(I18n.t("ai_helper.chat_channel.context.label"))}/, @response.body)
      end

      should "render imported messages as escaped plain text instead of markdown" do
        @conversation.messages << AiHelperMessage.new(
          role: "context", content: "Yamada: **bold** <script>alert(1)</script>"
        )
        @conversation.save!

        get :conversation, params: { id: @project.id, conversation_id: @conversation.id }

        assert_response :success
        assert_no_match(/<strong>bold<\/strong>/, @response.body)
        assert_no_match(/<script>alert\(1\)<\/script>/, @response.body)
        assert_match(/&lt;script&gt;/, @response.body)
      end

      should "render context messages without an avatar while user messages have one" do
        @conversation.messages << AiHelperMessage.new(role: "context", content: "Yamada: imported")
        @conversation.save!

        get :conversation, params: { id: @project.id, conversation_id: @conversation.id }

        assert_response :success
        assert_select ".aihelper-message-user strong",
                      text: I18n.t("ai_helper.chat_channel.context.label")
        assert_select ".aihelper-message-user strong",
                      text: @user.name
        context_html = @response.body.match(/aihelper-chat_channel.context.label.*?<\/strong>.*?<\/pre>/m)
        assert_no_match(/<img/, context_html.to_s,
                        "context messages must not render an avatar image")
      end

      should "render assistant answers containing a table with the list class" do
        @conversation.messages << AiHelperMessage.new(
          role: "assistant",
          content: "| col |\n|-----|\n| 1   |"
        )
        @conversation.save!

        get :conversation, params: { id: @project.id, conversation_id: @conversation.id }

        assert_response :success
        assert_select "table.list td", text: "1"
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
        post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello AI" } }

        assert_response :success
        post :call_llm, params: { id: @project.id, controller_name: "issues", action_name: "show", content_id: 1, additional_info: { key: "value" } }

        assert_response :success
      end

      should "call cleanup_old_conversations when saving conversation" do
        # Mock LLM to avoid actual API calls
        llm_mock = mock("RedmineAiHelper::Llm")
        message_mock = mock("AiHelperMessage")
        message_mock.stubs(:content).returns("普通の回答です。")
        message_mock.stubs(:content=)
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
        @conversation.stubs(:messages).returns(mock("messages").tap { |m| m.stubs(:<<) })
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

      should "render summary tables with the list class and keep other elements" do
        markdown = "## Summary heading\n\n- list item\n\n| col |\n|-----|\n| 1   |"
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(
          AiHelperSummaryCache.new(object_class: "Issue", object_id: @issue.id, content: markdown)
        )

        get :issue_summary, params: { id: @project.id, issue_id: @issue.id }

        assert_response :success
        assert_select ".ai-helper-summary-body table.list td", text: "1"
        assert_select ".ai-helper-summary-body h2", text: "Summary heading"
        assert_select ".ai-helper-summary-body ul li", text: "list item"
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

      should "stream the error and not cache it when summary generation fails" do
        RedmineAiHelper::Llm.any_instance.stubs(:issue_summary).raises(StandardError, "prompt template missing")
        AiHelperSummaryCache.stubs(:issue_cache).with(issue_id: @issue.id).returns(nil)
        AiHelperSummaryCache.expects(:update_issue_cache).never

        post :generate_issue_summary, params: { id: @issue.id }

        assert_response :success
        assert_match(/Error generating issue summary: prompt template missing/, @response.body)
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
        @llm.stubs(:generate_sub_issues).returns([ issue ])
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
          "2" => { subject: "Sub Issue 2", description: "Description 2", tracker_id: 1, fixed_version_id: nil }
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

      should "render summary tables with the list class" do
        markdown = "## Wiki heading\n\n| col |\n|-----|\n| 1   |"
        AiHelperSummaryCache.stubs(:wiki_cache).returns(
          AiHelperSummaryCache.new(object_class: "WikiPage", object_id: @wiki_page.id, content: markdown)
        )

        get :wiki_summary, params: { id: @wiki_page.id }

        assert_response :success
        assert_select ".ai-helper-summary-body table.list td", text: "1"
        assert_select ".ai-helper-summary-body h2", text: "Wiki heading"
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
          "1" => { subject: "", description: "Invalid issue", tracker_id: 1, check: true }
        }
      end

      should "handle validation errors when creating sub-issues" do
        # Mock issue save failure
        Issue.any_instance.stubs(:save).returns(false)
        Issue.any_instance.stubs(:errors).returns(mock("errors").tap do |errors|
          errors.stubs(:full_messages).returns([ "Subject can't be blank" ])
        end)

        post :add_sub_issues, params: { id: @issue.id, sub_issues: @sub_issue_params, tracker_id: 1 }

        assert_response :redirect
        assert_not_nil flash[:error]
      end
    end

    context "#add_sub_issues with assigned_to_id" do
      setup do
        @issue = Issue.new(subject: "Parent Issue", project: @project, author: @user, tracker_id: 1, status_id: 1)
        @issue.save!
        # User 2 is a member of project 1 with Manager role (assignable)
        @assignable_user = User.find(2)
      end

      should "assign a valid assignee to the sub-issue" do
        sub_issue_params = {
          "1" => { subject: "Sub Issue", description: "Desc", tracker_id: 1, check: true, assigned_to_id: @assignable_user.id }
        }
        post :add_sub_issues, params: { id: @issue.id, sub_issues: sub_issue_params, tracker_id: 1 }

        assert_response :redirect
        created_issue = Issue.where(parent_id: @issue.id).first

        assert_not_nil created_issue
        assert_equal @assignable_user.id, created_issue.assigned_to_id
      end

      should "create sub-issue without assignee when assigned_to_id is blank" do
        sub_issue_params = {
          "1" => { subject: "Sub Issue", description: "Desc", tracker_id: 1, check: true, assigned_to_id: "" }
        }
        post :add_sub_issues, params: { id: @issue.id, sub_issues: sub_issue_params, tracker_id: 1 }

        assert_response :redirect
        created_issue = Issue.where(parent_id: @issue.id).first

        assert_not_nil created_issue
        assert_nil created_issue.assigned_to_id
      end

      should "show error when assigned_to_id is not a valid assignable user" do
        sub_issue_params = {
          "1" => { subject: "Sub Issue", description: "Desc", tracker_id: 1, check: true, assigned_to_id: 99999 }
        }
        post :add_sub_issues, params: { id: @issue.id, sub_issues: sub_issue_params, tracker_id: 1 }

        assert_response :redirect
        assert_not_nil flash[:error]
        assert_equal 0, Issue.where(parent_id: @issue.id).count
      end
    end

    context "#assignable_users_for_tracker" do
      setup do
        @tracker = Tracker.find(1)
      end

      should "return assignable users as JSON for a given tracker" do
        get :assignable_users_for_tracker, params: { id: @project.id, tracker_id: @tracker.id }

        assert_response :success
        json = JSON.parse(response.body)

        assert_kind_of Array, json
        assert(json.all? { |u| u.key?("id") && u.key?("name") })
      end

      should "return assignable users when tracker_id is not provided" do
        get :assignable_users_for_tracker, params: { id: @project.id }

        assert_response :success
        json = JSON.parse(response.body)

        assert_kind_of Array, json
      end

      should "return assignable users when tracker_id is invalid" do
        get :assignable_users_for_tracker, params: { id: @project.id, tracker_id: 99999 }

        assert_response :success
        json = JSON.parse(response.body)

        assert_kind_of Array, json
      end

      should "include project members with assignable roles" do
        get :assignable_users_for_tracker, params: { id: @project.id, tracker_id: @tracker.id }
        json = JSON.parse(response.body)
        user_ids = json.map { |u| u["id"] }
        # User 2 is a member of project 1 with Manager role (assignable)
        assert_includes user_ids, 2
      end

      should "not include non-member users" do
        get :assignable_users_for_tracker, params: { id: @project.id, tracker_id: @tracker.id }
        json = JSON.parse(response.body)
        user_ids = json.map { |u| u["id"] }
        # User 4 is not a member of project 1
        assert_not_includes user_ids, 4
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
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success

        # Check that the response contains the expected content (HTML partial)
        assert_match(/Similar issue/, @response.body)
        assert_match(/85\.0%/, @response.body)
        assert_match(/3\.5 h/, @response.body)
        assert_match(/Updated/, @response.body)
      end

      should "display suggested hours when similar issues have spent_hours data" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/Estimated time suggestion/, @response.body)
        assert_match(/3\.5 h/, @response.body)
      end

      should "display suggested hours based on a single issue in Japanese locale" do
        @user.update_column(:language, "ja")
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/1件の類似チケットに基づく/, @response.body)
      end

      should "fall back to the English note in a locale that does not define the key" do
        @user.update_column(:language, "fr")
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/based on 1 similar issue\(s\)/, @response.body)
      end

      should "render a selection checkbox with data attributes for similar issues with spent_hours data" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/class="ai-helper-effort-checkbox"/, @response.body)
        assert_match(/checked/, @response.body)
        assert_match(/data-spent-hours="3\.5"/, @response.body)
        assert_match(/data-similarity-score="85\.0"/, @response.body)
        assert_match(/<td class="ai-helper-spent-hours">\s*<input[^>]*class="ai-helper-effort-checkbox"/, @response.body)
        assert_no_match(/<th><\/th>/, @response.body)
        assert_no_match(/<td class="ai-helper-effort-select">/, @response.body)
      end

      should "render an unchecked checkbox for similar issues without spent_hours data" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }, {
          id: 3,
          project: { name: "Test Project" },
          subject: "Unrecorded similar issue",
          status: { name: "Open" },
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 70.0,
          issue_url: "/issues/3"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        checkbox_2 = @response.body[/<input[^>]*name="ai_helper_effort_2"[^>]*>/]
        checkbox_3 = @response.body[/<input[^>]*name="ai_helper_effort_3"[^>]*>/]
        assert_match(/class="ai-helper-effort-checkbox"/, checkbox_2)
        assert_match(/checked="checked"/, checkbox_2)
        assert_match(/class="ai-helper-effort-checkbox"/, checkbox_3)
        assert_no_match(/checked="checked"/, checkbox_3)
        assert_no_match(/data-spent-hours=/, checkbox_3)
      end

      should "render an unchecked checkbox for similar issues with zero spent_hours" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        }, {
          id: 3,
          project: { name: "Test Project" },
          subject: "Zero spent hours similar issue",
          status: { name: "Open" },
          spent_hours: 0,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 70.0,
          issue_url: "/issues/3"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        checkbox_3 = @response.body[/<input[^>]*name="ai_helper_effort_3"[^>]*>/]
        assert_match(/class="ai-helper-effort-checkbox"/, checkbox_3)
        assert_no_match(/checked="checked"/, checkbox_3)
      end

      should "render a select-all checkbox in the spent-time column header when estimation is available" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/id="ai-helper-effort-select-all"/, @response.body)
      end

      should "render an apply button for the suggested hours" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          spent_hours: 3.5,
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_match(/id="ai-helper-apply-suggested-hours"/, @response.body)
        assert_match(/Apply to this issue&#39;s estimated time/, @response.body)
        assert_operator @response.body.index("</table>"), :<, @response.body.index('id="ai-helper-suggested-hours-block"')
      end

      should "not display suggested hours or selection controls when no similar issue has spent_hours data" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
        assert_no_match(/Estimated time suggestion/, @response.body)
        assert_no_match(/id="ai-helper-apply-suggested-hours"/, @response.body)
        assert_no_match(/id="ai-helper-effort-select-all"/, @response.body)
      end

      should "exclude current issue from results" do
        # Mock LLM find_similar_issues method (should already exclude current issue)
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success

        # Check that only the other issue is included (current issue excluded)
        assert_match(/Similar issue/, @response.body)
        # Check that only issue ID 2 is present, not the current issue ID 1
        assert_match(/>2</, @response.body)
        assert_no_match(/>#{@issue.id}</, @response.body)
      end

      should "return empty array when no similar issues found" do
        # Mock LLM find_similar_issues method returning empty array
        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns([])

        get :similar_issues, params: { id: @issue.id }

        assert_response :success

        # Check that no similar issues message is displayed
        assert_match(/No similar issues found/, @response.body)
      end

      should "handle vector search errors gracefully" do
        # Mock LLM find_similar_issues method raising an error
        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).raises(StandardError.new("Vector search failed"))

        get :similar_issues, params: { id: @issue.id }

        assert_response :internal_server_error

        response_data = JSON.parse(@response.body)

        assert_equal "Vector search failed", response_data["error"]
      end

      should "handle missing assigned_to_name gracefully" do
        # Mock LLM find_similar_issues method with nil assigned_to
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.zone.now,
          assigned_to: nil,
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.stubs(:find_similar_issues).with(issue: @issue, scope: "with_subprojects", project: @issue.project).returns(similar_issues)

        get :similar_issues, params: { id: @issue.id }

        assert_response :success

        # Check that the similar issue is displayed even without assigned_to_name
        assert_match(/Similar issue/, @response.body)
        assert_match(/85\.0%/, @response.body)
      end

      should "pass scope parameter to Llm" do
        @llm_mock.expects(:find_similar_issues)
                 .with(issue: @issue, scope: "current", project: @issue.project)
                 .returns([])

        get :similar_issues, params: { id: @issue.id, scope: "current" }

        assert_response :success
      end

      should "pass all scope to Llm" do
        @llm_mock.expects(:find_similar_issues)
                 .with(issue: @issue, scope: "all", project: @issue.project)
                 .returns([])

        get :similar_issues, params: { id: @issue.id, scope: "all" }

        assert_response :success
      end

      should "default scope to with_subprojects when not specified" do
        @llm_mock.expects(:find_similar_issues)
                 .with(issue: @issue, scope: "with_subprojects", project: @issue.project)
                 .returns([])

        get :similar_issues, params: { id: @issue.id }

        assert_response :success
      end

      should "fallback to default scope for invalid scope value" do
        @llm_mock.expects(:find_similar_issues)
                 .with(issue: @issue, scope: "with_subprojects", project: @issue.project)
                 .returns([])

        get :similar_issues, params: { id: @issue.id, scope: "invalid_scope" }

        assert_response :success
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

      should "draw two tables of different widths in the latest report PDF without Markdown table lines" do
        RedmineAiHelper::CustomLogger.instance.expects(:error).with(regexp_matches(/Error processing content for PDF/)).never
        Rails.cache.stubs(:fetch).returns("| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n\n| x | y |\n|---|---|\n| 4 | 5 |\n")

        get :project_health, params: { id: @project.id, format: :pdf }

        assert_response :success
        text = pdf_text(response.body)
        assert_equal(0, text.lines.count { |line| line.strip.match?(/\A\|.*\|\z/) })
        assert_no_match(/---/, text)
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

    context "#project_health_markdown" do
      should "export the posted body as a zip with unavailable chart directives" do
        post :project_health_markdown, params: { id: @project.id, health_report_content: "Text\n\n{{ai_helper_chart(status, version=12)}}\n\nMore" }

        assert_response :success
        assert_equal "application/zip", response.media_type
        base = "#{@project.identifier}-health-report-#{Date.current.strftime("%Y%m%d")}"
        assert_includes response.headers["Content-Disposition"], "#{base}.zip"
        entries = {}
        Zip::InputStream.open(StringIO.new(response.body)) do |io|
          while (entry = io.get_next_entry)
            entries[entry.name] = io.read.force_encoding("UTF-8")
          end
        end
        assert_equal [ "#{base}.md" ], entries.keys
        message = I18n.t("ai_helper.health_report_chart.unavailable") +
                  I18n.t("ai_helper.health_report_chart.errors.metrics_unavailable")
        assert_equal "Text\n\n> #{message}\n\nMore", entries["#{base}.md"]
      end

      should "redirect when the body is blank" do
        post :project_health_markdown, params: { id: @project.id, health_report_content: "" }

        assert_response :redirect
      end
    end

    context "#project_health_pdf" do
      should "report body chart directives as having no metrics" do
        post :project_health_pdf, params: { id: @project.id, health_report_content: "Text\n\n{{ai_helper_chart(status, version=12)}}\n\nMore" }

        assert_response :success
        inflated = response.body.b.scan(/stream\r?\n(.*?)endstream/m).map do |(data)|
          Zlib::Inflate.inflate(data)
        rescue Zlib::Error
          data
        end.join.delete("\x00").gsub(/\\([()])/, '\1')
        assert_includes inflated, I18n.t("ai_helper.health_report_chart.errors.metrics_unavailable")
      end

      should "draw two tables of different widths without Markdown table lines" do
        RedmineAiHelper::CustomLogger.instance.expects(:error).with(regexp_matches(/Error processing content for PDF/)).never

        post :project_health_pdf, params: { id: @project.id, health_report_content: "| a | b | c |\n|---|---|---|\n| 1 | 2 | 3 |\n\n| x | y |\n|---|---|\n| 4 | 5 |\n" }

        assert_response :success
        text = pdf_text(response.body)
        assert_equal(0, text.lines.count { |line| line.strip.match?(/\A\|.*\|\z/) })
        assert_no_match(/---/, text)
      end

      should "generate PDF from health report content" do
        health_content = "# Test Health Report\n\nThis is a test report."

        # Mock PDF generation
        @controller.stubs(:project_health_to_pdf).returns("PDF content")

        post :project_health_pdf, params: { id: @project.id, health_report_content: health_content }

        assert_response :success
        assert_equal "application/pdf", @response.content_type
        assert_match(/#{@project.identifier}-health-report-/, @response.headers["Content-Disposition"])
      end

      should "sanitize malicious content" do
        malicious_content = "<script>alert('xss')</script># Test Report\n<div>Content</div>"
        expected_sanitized = "# Test Report\n\nContent"

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
        assert_match(/data:/, @response.body)
      end

      should "send health_report_saved with the report id before finish_reason stop" do
        content = "Generated health report"
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:project_health_report).returns(content)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)
        report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: content)
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        body = @response.body
        saved_index = body.index("event: health_report_saved")
        stop_index = body.index('"finish_reason":"stop"')

        assert_not_nil saved_index, "health_report_saved event was not sent"
        assert_not_nil stop_index
        assert_operator saved_index, :<, stop_index
        assert_includes body, %(data: {"report_id": #{report.id}})
      end

      should "not send health_report_saved when the stored body differs from the LLM result" do
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:project_health_report).returns("Generated health report")
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)
        report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: "A different body")
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)
        logger_mock = mock("ai_helper_logger")
        logger_mock.stubs(:info)
        logger_mock.stubs(:error)
        logger_mock.expects(:warn).with do |message|
          message.include?("health report #{report.id}") && message.include?("project #{@project.id}")
        end
        @controller.stubs(:ai_helper_logger).returns(logger_mock)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        assert_not_includes @response.body, "health_report_saved"
      end

      should "send health_report_saved for the report the real Llm and ProjectAgent saved" do
        # The cross-layer contract (R-008): Llm#project_health_report returns
        # exactly the body ProjectAgent saved, so the event's id points at a
        # record whose body equals what was streamed. Only the LLM call and
        # the metrics tool are stubbed; prompt build, save and the event stay
        # real.
        RedmineAiHelper::Tools::ProjectTools.any_instance.stubs(:get_metrics)
            .returns({ issue_statistics: { total_issues: 0 } })
        content = "Generated health report body"
        RedmineAiHelper::Agents::ProjectAgent.any_instance.stubs(:think_chat).returns(content)
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        saved = AiHelperHealthReport.for_project(@project.id).by_user(@user.id).sorted.first
        assert_not_nil saved, "the agent should have saved the generated report"
        assert_equal content, saved.health_report
        assert_includes @response.body, %(data: {"report_id": #{saved.id}})
      end

      should "not send health_report_saved when the LLM call raises and nothing is saved" do
        RedmineAiHelper::Tools::ProjectTools.any_instance.stubs(:get_metrics)
            .returns({ issue_statistics: { total_issues: 0 } })
        RedmineAiHelper::Agents::ProjectAgent.any_instance.stubs(:think_chat)
            .raises(StandardError, "LLM unavailable")
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        assert_not_includes @response.body, "health_report_saved"
        assert_includes @response.body, "LLM unavailable"
      end

      should "not send health_report_saved when only an older report has the same body" do
        content = "Generated health report"
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:project_health_report).returns(content)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)
        AiHelperHealthReport.create!(project: @project, user: @user, health_report: content, created_at: 2.days.ago)
        AiHelperHealthReport.create!(project: @project, user: @user, health_report: "A newer, different body")
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        assert_not_includes @response.body, "health_report_saved"
      end

      should "not send health_report_saved for another user's report with the same body" do
        content = "Generated health report"
        llm_mock = mock("RedmineAiHelper::Llm")
        llm_mock.stubs(:project_health_report).returns(content)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)
        AiHelperHealthReport.create!(project: @project, user: User.find(2), health_report: content)
        Rails.cache.stubs(:delete)
        Rails.cache.stubs(:write)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success
        assert_not_includes @response.body, "health_report_saved"
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
        assert_match(/data:/, @response.body)
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
        session[:ai_helper][:conversation_id]

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
        error.set_backtrace([ "line1", "line2", "line3" ])

        # Mock to avoid actual LLM calls but still trigger error path
        llm_mock = mock("llm")
        llm_mock.stubs(:project_health_report).raises(error)
        RedmineAiHelper::Llm.stubs(:new).returns(llm_mock)

        get :generate_project_health, params: { id: @project.id }

        assert_response :success

        # Check that streaming response started (initial chunk)
        assert_match(/chatcmpl-/, @response.body)
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
          "1" => { subject: "Sub Issue", description: "Description", tracker_id: 1, check: true, fixed_version_id: "" }
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
        assert_match(/data:/, @response.body)
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
        assert_match(/chatcmpl-test123456789abc/, @response.body)
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

        assert json_response.key?("suggestion")
        assert_equal "This is a suggested completion.", json_response["suggestion"]
      end

      should "return error for non-JSON request in suggest_completion" do
        issue = Issue.find(1)

        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id, text: "Some text" }

        assert_response :unsupported_media_type
        json_response = JSON.parse(response.body)

        assert_equal "Unsupported Media Type", json_response["error"]
      end


      should "return error for empty text in suggest_completion" do
        issue = Issue.find(1)

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "", cursor_position: 0 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)

        assert_equal "Text is required", json_response["error"]
      end

      should "return error for text too long in suggest_completion" do
        issue = Issue.find(1)
        long_text = "a" * 5001

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: long_text, cursor_position: 100 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)

        assert_equal "Text too long", json_response["error"]
      end

      should "return error for invalid cursor position in suggest_completion" do
        issue = Issue.find(1)
        text = "Test text"

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: text, cursor_position: text.length + 1 }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)

        assert_equal "Invalid cursor position", json_response["error"]
      end

      should "return an empty suggestion when the completion LLM request times out" do
        issue = Issue.find(1)
        RedmineAiHelper::Agents::IssueReadAgent.any_instance.stubs(:chat)
          .raises(Faraday::TimeoutError.new("execution expired"))

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error", cursor_position: 16 }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert_equal "", json_response["suggestion"]
      end

      should "handle LLM error gracefully in suggest_completion" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).raises(StandardError, "LLM error")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error", cursor_position: 16 }.to_json

        assert_response :internal_server_error
        json_response = JSON.parse(response.body)

        assert_equal "Failed to generate suggestion", json_response["error"]
      end

      should "handle suggest_completion with nil cursor position" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns("completion text")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Login page error" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert json_response.key?("suggestion")
        assert_equal "completion text", json_response["suggestion"]
      end

      should "suggest completion for notes context type" do
        issue = Issue.find(1)
        RedmineAiHelper::Llm.any_instance.stubs(:generate_text_completion).returns("I have reviewed this issue.")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "I have reviewed", cursor_position: 15, context_type: "note" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert json_response.key?("suggestion")
        assert_equal "I have reviewed this issue.", json_response["suggestion"]
      end

      should "return error for invalid context_type" do
        issue = Issue.find(1)

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Test text", cursor_position: 5, context_type: "invalid" }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)

        assert_equal "Invalid context_type. Must be 'description' or 'note'", json_response["error"]
      end

      should "return error for note context_type without existing issue" do
        issue = Issue.find(1)
        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: "new" },
             body: { text: "Test note", cursor_position: 5, context_type: "note" }.to_json

        assert_response :bad_request
        json_response = JSON.parse(response.body)

        assert_equal "Issue is required for note completion", json_response["error"]
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

        assert json_response.key?("suggestion")
        assert_equal " and I agree with the analysis.", json_response["suggestion"]

        # Clean up
        journal.destroy
      end

      # Integration tests for refactored architecture
      should "test refactored generate_text_completion integration" do
        issue = Issue.find(1)

        # Test that the new architecture works end-to-end
        # The controller should call llm.rb which delegates to IssueReadAgent
        @request.headers["Content-Type"] = "application/json"

        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "This is a test issue", cursor_position: 17, context_type: "description" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert json_response.key?("suggestion")
        # The response should be a string (empty in test environment due to mocking)
        assert_kind_of String, json_response["suggestion"]
      end

      should "test prompt loader integration through agent" do
        issue = Issue.find(1)

        # Mock the PromptLoader to verify it's being used
        mock_prompt = mock("Prompt")
        mock_prompt.stubs(:format).returns("Mocked prompt text")

        # The IssueReadAgent should use PromptLoader via load_prompt
        RedmineAiHelper::Agents::IssueReadAgent.any_instance.expects(:load_prompt)
          .with("issue_read_agent/inline_completion")
          .returns(mock_prompt)

        RedmineAiHelper::Agents::IssueReadAgent.any_instance.stubs(:chat).returns("Mocked completion")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "Test prompt loading", cursor_position: 4, context_type: "description" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert_equal "Mocked completion", json_response["suggestion"]
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

        RedmineAiHelper::Agents::IssueReadAgent.any_instance.expects(:load_prompt)
          .with("issue_read_agent/note_inline_completion")
          .returns(mock_prompt)

        RedmineAiHelper::Agents::IssueReadAgent.any_instance.stubs(:chat).returns("Contextual note completion")

        @request.headers["Content-Type"] = "application/json"
        post :suggest_completion, params: { id: issue.project.id, issue_id: issue.id },
             body: { text: "I agree with", cursor_position: 12, context_type: "note" }.to_json

        assert_response :success
        json_response = JSON.parse(response.body)

        assert_equal "Contextual note completion", json_response["suggestion"]

        # Clean up
        journal.destroy
      end
    end

    context "CSRF protection" do
      should "reject JSON format POST without CSRF token" do
        ActionController::Base.allow_forgery_protection = true
        begin
          post :project_health_pdf, params: { id: @project.id, health_report_content: "test", format: :json }

          assert_includes [ 403, 422 ], response.code.to_i
        ensure
          ActionController::Base.allow_forgery_protection = false
        end
      end

      should "reject JSON format chat POST without CSRF token" do
        ActionController::Base.allow_forgery_protection = true
        begin
          post :chat, params: { id: @project.id, ai_helper_message: { content: "Hello" }, format: :json }

          assert_includes [ 403, 422 ], response.code.to_i
        ensure
          ActionController::Base.allow_forgery_protection = false
        end
      end
    end

    context "#check_duplicates" do
      setup do
        @llm_mock = mock("RedmineAiHelper::Llm")
        RedmineAiHelper::Llm.stubs(:new).returns(@llm_mock)
      end

      should "return similar issues successfully" do
        similar_issues = [ {
          id: 2,
          project: { name: "Test Project" },
          subject: "Similar issue",
          status: { name: "Open" },
          updated_on: Time.zone.now,
          assigned_to: { name: "Test User" },
          similarity_score: 85.0,
          issue_url: "/issues/2"
        } ]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "Test subject", description: "Test description", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Test subject", description: "Test description" }.to_json

        assert_response :success
        assert_match(/Similar issue/, @response.body)
        assert_match(/85\.0%/, @response.body)
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

        assert_predicate response_data["error"], :present?
      end

      should "return empty result when no similar issues found" do
        @llm_mock.stubs(:find_similar_issues_by_content).returns([])

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Unique subject", description: "Unique description" }.to_json

        assert_response :success
        assert_match(/No similar issues found|類似するチケットが見つかりませんでした/, @response.body)
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
        similar_issues = [ {
          id: 3,
          project: { name: "Test Project" },
          subject: "Matching issue",
          status: { name: "New" },
          updated_on: Time.zone.now,
          assigned_to: nil,
          similarity_score: 72.0,
          issue_url: "/issues/3"
        } ]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "Test subject", description: "", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "Test subject", description: "" }.to_json

        assert_response :success
        assert_match(/Matching issue/, @response.body)
      end

      should "work with only description provided" do
        similar_issues = [ {
          id: 4,
          project: { name: "Test Project" },
          subject: "Another matching issue",
          status: { name: "In Progress" },
          updated_on: Time.zone.now,
          assigned_to: { name: "Developer" },
          similarity_score: 68.5,
          issue_url: "/issues/4"
        } ]

        @llm_mock.expects(:find_similar_issues_by_content)
                 .with(subject: "", description: "Test description", project: @project)
                 .returns(similar_issues)

        @request.headers["Content-Type"] = "application/json"
        post :check_duplicates, params: { id: @project.id },
             body: { subject: "", description: "Test description" }.to_json

        assert_response :success
        assert_match(/Another matching issue/, @response.body)
      end
    end


    context "#call_llm interactive options" do
      setup do
        AiHelperConversation.stubs(:cleanup_old_conversations)
        @request.session[:ai_helper] = { conversation_id: @conversation.id }
        # Helper lambda: creates a real object whose chat method calls stream_proc (simulating LLM streaming)
        @make_streaming_llm = lambda do |llm_response|
          stub_llm = Object.new
          stub_llm.define_singleton_method(:chat) do |_conv, stream_proc, _opt|
            stream_proc.call(llm_response) if stream_proc.respond_to?(:call)
            AiHelperMessage.new(role: "assistant", content: llm_response)
          end
          RedmineAiHelper::Llm.stubs(:new).returns(stub_llm)
          stub_llm
        end
      end

      should "include interactive_options SSE event when LLM response contains options block" do
        options_block = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"はい","value":"はい"},{"label":"いいえ","value":"いいえ"}]}-->'
        @make_streaming_llm.call("この課題を次のバージョンに移動しますか？\n\n#{options_block}")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_includes @response.body, "event: interactive_options"
        assert_includes @response.body, '"choices"'
        assert_includes @response.body, '"label":"はい"'
      end

      should "not include interactive_options SSE event when LLM response has no options block" do
        @make_streaming_llm.call("普通の回答です。")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_not_includes @response.body, "event: interactive_options"
      end

      should "save message content without options block" do
        options_block = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"はい","value":"はい"},{"label":"いいえ","value":"いいえ"}]}-->'
        @make_streaming_llm.call("この課題を次のバージョンに移動しますか？\n\n#{options_block}")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        saved_message = AiHelperMessage.where(role: "assistant").last

        assert_not_nil saved_message
        assert_not_includes saved_message.content, "AIHELPER_OPTIONS"
      end

      should "include interactive_options event with 3 choices" do
        block = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"High","value":"High"},{"label":"Normal","value":"Normal"},{"label":"Low","value":"Low"}]}-->'
        @make_streaming_llm.call("優先度を選択してください。\n\n#{block}")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_includes @response.body, "event: interactive_options"
        data_match = @response.body.match(/event: interactive_options\ndata: (.+)\n/)

        assert_not_nil data_match
        data = JSON.parse(data_match[1])

        assert_equal 3, data["choices"].length
      end

      should "include only 5 choices when LLM response has 6 choices" do
        block = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"A","value":"A"},{"label":"B","value":"B"},{"label":"C","value":"C"},{"label":"D","value":"D"},{"label":"E","value":"E"},{"label":"F","value":"F"}]}-->'
        @make_streaming_llm.call("どれですか？\n\n#{block}")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_includes @response.body, "event: interactive_options"
        data_match = @response.body.match(/event: interactive_options\ndata: (.+)\n/)

        assert_not_nil data_match
        data = JSON.parse(data_match[1])

        assert_equal 5, data["choices"].length
      end

      should "handle second call_llm with conversation history correctly" do
        user_message = AiHelperMessage.new(content: "選択してください", role: "user")
        @conversation.messages << user_message

        options_block = '<!--AIHELPER_OPTIONS:{"choices":[{"label":"はい","value":"はい"},{"label":"いいえ","value":"いいえ"}]}-->'
        @make_streaming_llm.call("確認しますか？\n\n#{options_block}")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_includes @response.body, "event: interactive_options"
      end

      should "not send interactive_options event on second call when no options block" do
        user_message = AiHelperMessage.new(content: "はい", role: "user")
        @conversation.messages << user_message

        @make_streaming_llm.call("了解しました。処理を実行します。")

        post :call_llm, params: {
          id: @project.id,
          controller_name: "issues",
          action_name: "show",
          content_id: 1,
          additional_info: { key: "value" }
        }

        assert_response :success
        assert_not_includes @response.body, "event: interactive_options"
      end
    end

    context "chat sidebar" do
      setup do
        get :reload, params: { id: @project.id }
        RedmineAiHelper::Util::PermissionChecker.stubs(:module_enabled?).returns(true)
        setting_mock = stub("AiHelperSetting", model_profile: stub("AiHelperModelProfile"), read_only_mode: false)
        AiHelperSetting.stubs(:find_or_create).returns(setting_mock)
        @view = @controller.view_context
        @view.render(partial: "ai_helper/chat/sidebar")
        @sidebar_html = @view.content_for(:sidebar)
      end

      should "include issue_base in ai_helper_urls" do
        assert_match %r{issue_base:}, @sidebar_html
      end

      should "set issue_base to a path ending with /issues/__ID__" do
        assert_match %r{issue_base:.*\/issues\/__ID__}, @sidebar_html
      end
    end
  end
end
