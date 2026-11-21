require_relative "../test_helper"

class AiHelperViewHookTest < ActionController::TestCase
  tests IssuesController

  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories,
           :versions, :custom_fields, :custom_values, :groups_users, :members, :member_roles, :roles,
           :user_preferences, :wikis, :wiki_pages, :wiki_contents

  def setup
    @controller = IssuesController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create
    @user = User.find(1) # admin
    @project = projects(:projects_001)
    @issue = issues(:issues_001)
    @request.session[:user_id] = @user.id
    User.current = @user

    enabled_module = EnabledModule.new
    enabled_module.project_id = @project.id
    enabled_module.name = "ai_helper"
    enabled_module.save!
  end

  test "head element must not contain any block-level div elements" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_equal 0, doc.css("head div").length, "expected no <div> elements inside <head>"
    assert_nil doc.at_css("head #ai-helper-stuff-todo-modal")
    assert_nil doc.at_css("head #ai-helper-stuff-todo-overlay")
  end

  test "stuff todo modal elements are rendered inside body instead of head" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("body #ai-helper-stuff-todo-overlay"), "expected overlay element inside <body>"
    assert doc.at_css("body #ai-helper-stuff-todo-modal"), "expected modal element inside <body>"
  end

  test "another plugin's head hook output registered after ai_helper stays inside head" do
    original_listener_classes = Redmine::Hook.class_variable_get(:@@listener_classes).dup

    # Registering a Redmine::Hook::ViewListener subclass auto-registers it
    # (Redmine::Hook::Listener.inherited), placing it after ai_helper's own
    # listener which was already registered when the plugin loaded.
    Class.new(Redmine::Hook::ViewListener) do
      render_on :view_layouts_base_html_head, inline: '<link rel="stylesheet" href="/dummy-other-plugin.css">'
    end

    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css('head link[href="/dummy-other-plugin.css"]'),
           "expected the other plugin's <link> to remain inside <head>"
  ensure
    Redmine::Hook.class_variable_set(:@@listener_classes, original_listener_classes)
    Redmine::Hook.clear_listeners_instances
  end

  test "meta tags used by stuff todo JS are still rendered inside head" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css('head meta[name="ai-helper-stuff-todo-url"]')
    assert doc.at_css('head meta[name="ai-helper-stuff-todo-loading"]')
    assert doc.at_css('head meta[name="ai-helper-stuff-todo-error"]')
  end

  test "stuff todo modal DOM structure is preserved inside body" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("body #ai-helper-stuff-todo-overlay")
    assert doc.at_css("body #ai-helper-stuff-todo-modal")
    close_button = doc.at_css("body #ai-helper-stuff-todo-close")
    assert close_button
    assert close_button["aria-label"].present?
    assert doc.at_css("body #ai-helper-stuff-todo-body")
  end

  test "journal edit aids script is included after the typo checker and editor controls scripts" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    srcs = doc.css("script[src]").map { |s| s["src"] }
    # Asset digests suffix the basename, so match on the path without the extension
    index_of = ->(file) { srcs.index { |src| src.include?(file) } }
    expect = %w[
      autocompletion/ai_helper_auto_completion
      shared/ai_helper_editor_controls
      typo_checker/ai_helper_typo_checker
      typo_checker/ai_helper_typo_suggestion_overlay
      autocompletion/ai_helper_journal_edit_aids
    ]
    expect.each do |file|
      assert index_of.call(file), "expected #{file} to be included on the issue page"
    end
    expect.each_cons(2) do |before, after|
      assert index_of.call(before) < index_of.call(after),
             "expected #{after} to be included after #{before}"
    end
  end

  test "issue page typo overlay labels are unchanged when built by TypoCheckLabels" do
    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    overlay = doc.at_css("#ai-helper-issue-typo-overlay")
    assert overlay, "expected the issue typo overlay to be rendered"
    labels = JSON.parse(overlay["data-config"])["labels"]
    expected = %w[
      suggestionsTitle noSuggestions checkButton checking acceptSuggestion
      dismissSuggestion acceptAll dismissAll errorOccurred correctionTooltip
      applyFailed
    ]
    assert_equal expected.sort, labels.keys.sort
    expected.each do |key|
      assert_equal I18n.t("ai_helper.typo_check.#{key.underscore}"), labels[key]
    end
  end

  test "no stuff todo elements are rendered when ai_helper module is disabled" do
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_nil doc.at_css("#ai-helper-stuff-todo-overlay")
    assert_nil doc.at_css("#ai-helper-stuff-todo-modal")
    assert_nil doc.at_css('meta[name="ai-helper-stuff-todo-url"]')
  end

  test "no stuff todo elements are rendered when ai_helper module is disabled even if all_projects_scope is ON (FR-007/FR-008)" do
    AiHelperSetting.stubs(:all_projects_scope?).returns(true)
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_nil doc.at_css("#ai-helper-stuff-todo-overlay")
    assert_nil doc.at_css("#ai-helper-stuff-todo-modal")
    assert_nil doc.at_css('meta[name="ai-helper-stuff-todo-url"]')
  end

  # --- Chat popup (083-chat-form-popup) ---

  test "sidebar header renders the popup open button before the fold arrow and the close button after it" do
    get :show, params: { id: @issue.id }
    assert_response :success

    header = Nokogiri::HTML(@response.body).at_css("#aihelper-sidebar .aihelper-header")
    assert header, "expected the AI Helper header inside #aihelper-sidebar"
    open_button = header.at_css("#aihelper-popup-open")
    close_button = header.at_css("#aihelper-popup-close")
    arrow = header.at_css(".aihelper-arrow-button")
    assert open_button, "expected #aihelper-popup-open"
    assert close_button, "expected #aihelper-popup-close"
    assert arrow, "expected .aihelper-arrow-button"

    children = header.element_children
    assert_operator children.index(open_button), :<, children.index(arrow)
    assert_operator children.index(close_button), :>, children.index(arrow)
    assert_nil open_button["title"], "popup buttons intentionally have no tooltip"
    assert_nil close_button["title"], "popup buttons intentionally have no tooltip"
    assert_equal I18n.t(:label_ai_helper_popup_open), open_button["aria-label"]
    assert_equal I18n.t(:label_ai_helper_popup_close), close_button["aria-label"]
    assert open_button.at_css("svg"), "expected an icon in the open button"
    assert close_button.at_css("svg"), "expected an icon in the close button"
  end

  test "sidebar renders eight popup resize handles as direct children" do
    get :show, params: { id: @issue.id }
    assert_response :success

    sidebar = Nokogiri::HTML(@response.body).at_css("#aihelper-sidebar")
    handles = sidebar.element_children.select { |e| e["class"].to_s.split.include?("aihelper-popup-resize") }
    assert_equal %w[e n ne nw s se sw w], handles.map { |e| e["data-edge"] }.sort
  end

  test "head loads the popup script after the chat script and checks the popup flag right after setUserId" do
    get :show, params: { id: @issue.id }
    assert_response :success

    head = Nokogiri::HTML(@response.body).at_css("head")
    scripts = head.css("script")
    srcs = scripts.map { |e| e["src"].to_s }
    chat_index = srcs.index { |src| src.match?(%r{/chat/ai_helper_chat(-[0-9a-f]+)?\.js\z}) }
    popup_index = srcs.index { |src| src.match?(%r{/chat/ai_helper_chat_popup(-[0-9a-f]+)?\.js\z}) }
    assert chat_index, "expected ai_helper_chat.js in head"
    assert popup_index, "expected ai_helper_chat_popup.js in head"
    assert_operator popup_index, :>, chat_index

    set_user_index = scripts.index { |e| e["src"].nil? && e.text.include?("ai_helper.setUserId") }
    assert set_user_index, "expected the setUserId inline script"
    flag_script = scripts[set_user_index + 1]
    assert_nil flag_script["src"]
    assert_includes flag_script.text, "aihelper-popup-open_#{@user.id}"
    assert_includes flag_script.text, "aihelper-popup-pending"
    # The open state is per tab, so it must be read from sessionStorage and compared with 'true'.
    assert_includes flag_script.text, "sessionStorage.getItem('aihelper-popup-open_#{@user.id}') === 'true'"
    assert_not_includes flag_script.text, "localStorage"

    layout_index = srcs.index { |src| src.match?(%r{/chat/ai_helper_chat_popup_layout(-[0-9a-f]+)?\.js\z}) }
    assert layout_index, "expected ai_helper_chat_popup_layout.js in head"
    assert_operator layout_index, :<, popup_index
  end

  # --- Issue form notes controls (088-fix-issue-form-rerender) ---

  test "edit page renders the notes controls once inside fieldset#add_notes and not inside #all_attributes" do
    get :edit, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    notes_fieldset = doc.at_css("fieldset#add_notes")
    assert notes_fieldset, "expected fieldset#add_notes to be rendered on the edit page"
    all_attributes = doc.at_css("#all_attributes")
    assert all_attributes, "expected #all_attributes to be rendered on the edit page"

    assert_equal 1, doc.css("#ai-helper-notes-checkbox-container").length,
                 "expected exactly one notes checkbox container on the edit page"
    assert_equal 1, doc.css("#ai-helper-typo-control-panel-notes").length,
                 "expected exactly one notes typo control panel on the edit page"
    assert notes_fieldset.at_css("#ai-helper-notes-checkbox-container"),
           "expected the notes checkbox container inside fieldset#add_notes"
    assert notes_fieldset.at_css("#ai-helper-typo-control-panel-notes"),
           "expected the notes typo control panel inside fieldset#add_notes"
    assert_nil all_attributes.at_css("#ai-helper-notes-checkbox-container"),
               "expected no notes checkbox container inside #all_attributes"
    assert_nil all_attributes.at_css("#ai-helper-typo-control-panel-notes"),
               "expected no notes typo control panel inside #all_attributes"
  end

  test "new issue page does not render the notes controls" do
    get :new, params: { project_id: @project.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("#all_attributes"), "expected #all_attributes on the new issue page"
    assert_nil doc.at_css("#ai-helper-notes-checkbox-container")
    assert_nil doc.at_css("#ai-helper-typo-control-panel-notes")
  end

  test "new issue form re-render response (issues/new.js) does not contain the notes controls" do
    get :new, params: { project_id: @project.id }, xhr: true
    assert_response :success

    # Positive controls (CRF-033): the response is the re-rendered form that
    # carries the AI Helper config container, so the negative assertions
    # below search a region that really was rendered
    assert_includes @response.body, "replaceIssueFormWith"
    assert_includes @response.body, "ai-helper-issue-textarea-overlay"
    assert_not_includes @response.body, "ai-helper-notes-checkbox-container"
    assert_not_includes @response.body, "ai-helper-typo-control-panel-notes"
  end

  test "edit form re-render response (issues/edit.js) does not contain the notes controls" do
    get :edit, params: { id: @issue.id }, xhr: true
    assert_response :success

    assert_includes @response.body, "replaceIssueFormWith"
    assert_includes @response.body, "ai-helper-issue-textarea-overlay"
    assert_not_includes @response.body, "ai-helper-notes-checkbox-container"
    assert_not_includes @response.body, "ai-helper-typo-control-panel-notes"
  end

  test "edit page renders no notes controls when the ai_helper module is disabled" do
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

    get :edit, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("fieldset#add_notes"), "expected fieldset#add_notes (the hook region) to be rendered"
    assert_nil doc.at_css("#ai-helper-notes-checkbox-container")
    assert_nil doc.at_css("#ai-helper-typo-control-panel-notes")
  end

  test "a failed update that moves the issue to a project without the module renders the config container and the notes controls together" do
    # The overlay partial judges by @project (the page-load project) while the
    # notes controls used issue.project, which a failed update has already
    # switched to the target project: the two must agree (ADR-073)
    other_project = projects(:projects_003)
    EnabledModule.where(project_id: other_project.id, name: "ai_helper").destroy_all

    put :update, params: { id: @issue.id, issue: { project_id: other_project.id, subject: "" } }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("#all_attributes"), "expected the edit form to be re-rendered after the failed update"
    assert_equal other_project.id, assigns(:issue).project_id, "expected the failed update to have switched the issue's project"
    assert doc.at_css("#ai-helper-issue-textarea-overlay"), "expected the config container (judged by @project)"
    assert doc.at_css("fieldset#add_notes #ai-helper-notes-checkbox-container"),
           "expected the notes controls to be rendered whenever the config container is"
    assert doc.at_css("fieldset#add_notes #ai-helper-typo-control-panel-notes")
  end

  test "edit page renders no notes controls when the issue attributes are not editable" do
    Issue.any_instance.stubs(:attributes_editable?).returns(false)

    get :edit, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("fieldset#add_notes"), "expected fieldset#add_notes (the hook region) to be rendered"
    assert_nil doc.at_css("#ai-helper-notes-checkbox-container")
    assert_nil doc.at_css("#ai-helper-typo-control-panel-notes")
  end
end

# Verifies the body_bottom stuff todo modal partial guards safely when there
# is no project context at all (e.g. My page), unlike IssuesController#show
# above which always has a project. Needs its own ActionController::TestCase
# because it exercises MyController rather than IssuesController.
class AiHelperViewHookNoProjectContextTest < ActionController::TestCase
  tests MyController

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules, :user_preferences

  def setup
    @controller = MyController.new
    @request = ActionController::TestRequest.create(@controller.class)
    @response = ActionDispatch::TestResponse.create
    @request.session[:user_id] = User.find(1).id # admin
  end

  test "my page renders successfully without stuff todo elements" do
    get :page

    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_nil doc.at_css("#ai-helper-stuff-todo-overlay")
    assert_nil doc.at_css("#ai-helper-stuff-todo-modal")
  end
end
