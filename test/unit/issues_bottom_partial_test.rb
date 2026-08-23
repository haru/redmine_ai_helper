# frozen_string_literal: true

require_relative "../test_helper"

class IssuesBottomPartialTest < ActionView::TestCase
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules, :issues, :trackers, :issue_statuses

  setup do
    @project = projects(:projects_001)
    @project.enable_module!(:ai_helper)
    @user = users(:users_001)
    @issue = issues(:issues_001)

    User.current = @user

    # Ensure the user has view_ai_helper permission
    role = roles(:roles_001)
    role.add_permission!(:view_ai_helper)

    # Stub AiHelperSetting so no real DB records needed
    @mock_setting = mock("AiHelperSetting")
    @mock_setting.stubs(:model_profile).returns(mock("profile"))
    AiHelperSetting.stubs(:find_or_create).returns(@mock_setting)
    AiHelperSetting.stubs(:vector_search_enabled?).returns(true)
    AiHelperSetting.stubs(:vector_search_enabled_for?).returns(true)
  end

  teardown do
    User.current = nil
  end

  context "similar issues section" do
    context "scope toggle" do
      should "render scope toggle container" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_includes html, "ai-helper-similar-issues-scope"
      end

      should "render radio button for current project scope" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_match(/<input[^>]+type="radio"[^>]+name="ai_helper_scope"[^>]+value="current"/, html)
      end

      should "render radio button for with_subprojects scope" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_match(/<input[^>]+type="radio"[^>]+name="ai_helper_scope"[^>]+value="with_subprojects"/, html)
      end

      should "render radio button for all projects scope" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_match(/<input[^>]+type="radio"[^>]+name="ai_helper_scope"[^>]+value="all"/, html)
      end

      should "default to with_subprojects scope checked" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_match(/<input[^>]+type="radio"[^>]+name="ai_helper_scope"[^>]+value="with_subprojects"[^>]+checked/, html)
      end

      should "render scope labels in current locale" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_includes html, l(:ai_helper_scope_current_project)
        assert_includes html, l(:ai_helper_scope_with_subprojects)
        assert_includes html, l(:ai_helper_scope_all_projects)
      end
    end

    context "project gating" do
      should "render similar issues section when project is a vector target" do
        AiHelperSetting.stubs(:vector_search_enabled_for?).returns(true)

        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_includes html, "ai-helper-similar-issues-button"
      end

      should "not render similar issues section when project is not a vector target" do
        AiHelperSetting.stubs(:vector_search_enabled_for?).returns(false)

        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_not_includes html, "ai-helper-similar-issues-button"
      end
    end

    context "JavaScript bridge" do
      # getSelectedScope()/similar-issues scope handling was extracted to
      # assets/javascripts/ai_helper_issue_summary.js (047-erb-js-refactoring);
      # that behavior (appending the checked scope as a query param) is
      # characterized in test/javascript/ai_helper_issue_summary.test.js. This
      # view spec only checks the ERB->JS bridge contract: the fieldset's
      # data-config carries the URL the JS-side scope logic needs, and the
      # button wires up to the JS-side init function by name.
      should "pass the similar issues URL to the JS bridge via data-config" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_match(/data-config='[^']*&quot;similarIssuesUrl&quot;:&quot;[^&]*similar_issues[^&]*&quot;/, html)
      end

      should "wire the similar issues button to the findSimilarIssues bridge function" do
        html = render(partial: "ai_helper/issues/bottom", locals: {})

        assert_includes html, "findSimilarIssues()"
      end
    end
  end
end
