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

  test "no stuff todo elements are rendered when ai_helper module is disabled" do
    EnabledModule.where(project_id: @project.id, name: "ai_helper").destroy_all

    get :show, params: { id: @issue.id }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_nil doc.at_css("#ai-helper-stuff-todo-overlay")
    assert_nil doc.at_css("#ai-helper-stuff-todo-modal")
    assert_nil doc.at_css('meta[name="ai-helper-stuff-todo-url"]')
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
