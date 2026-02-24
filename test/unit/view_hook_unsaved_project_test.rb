# frozen_string_literal: true

require_relative "../test_helper"

# Regression test for PR #221: Ensure hook partials render safely with unsaved projects
# During project/subproject creation, @project is often an unsaved Project.new
# This test ensures partials don't raise errors when project is unsaved
class ViewHookUnsavedProjectTest < ActionView::TestCase
  include ApplicationHelper
  include Rails.application.routes.url_helpers

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules

  setup do
    @user = users(:users_001)
    User.current = @user

    # Create a persisted project for comparison
    @saved_project = projects(:projects_001)
    @saved_project.enable_module!(:ai_helper)

    # Create an unsaved project (as in project/subproject creation)
    @unsaved_project = Project.new

    # Stub AiHelperSetting to avoid DB requirements
    @mock_setting = mock("AiHelperSetting")
    @mock_setting.stubs(:model_profile).returns(mock("profile"))
    AiHelperSetting.stubs(:find_or_create).returns(@mock_setting)
    AiHelperSetting.stubs(:vector_search_enabled?).returns(true)

    # Ensure user has view_ai_helper permission
    role = roles(:roles_001)
    role.add_permission!(:view_ai_helper)
  end

  teardown do
    User.current = nil
  end

  context "view_layouts_base_html_head hook" do
    context "with unsaved project" do
      should "render html_header partial without error" do
        @project = @unsaved_project
        @issue = nil
        @wiki_page = nil

        # Should not raise an error, even with unsaved project
        assert_nothing_raised do
          html = render(partial: "ai_helper/shared/html_header", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end

    context "with nil project" do
      should "render html_header partial without error" do
        @project = nil
        @issue = nil
        @wiki_page = nil

        assert_nothing_raised do
          html = render(partial: "ai_helper/shared/html_header", locals: {})
          # Should return empty string since project is nil
          assert_equal "", html
        end
      end
    end
  end

  context "view_layouts_base_body_top hook (sidebar)" do
    context "with unsaved project" do
      should "render sidebar partial without error" do
        @project = @unsaved_project
        @controller = Struct.new(:controller_name).new("issues")

        assert_nothing_raised do
          html = render(partial: "ai_helper/chat/sidebar", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_issues_show_details_bottom hook" do
    context "with unsaved project" do
      should "render bottom partial without error" do
        @project = @unsaved_project
        @issue = Issue.new
        @issue.stubs(:project).returns(@unsaved_project)
        AiHelperSummaryCache.stubs(:issue_cache).returns(nil)

        assert_nothing_raised do
          html = render(partial: "ai_helper/issues/bottom", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_issues_edit_notes_bottom hook" do
    context "with unsaved project" do
      should "render form partial without error" do
        @project = @unsaved_project
        @issue = Issue.new
        @issue.stubs(:project).returns(@unsaved_project)

        assert_nothing_raised do
          html = render(partial: "ai_helper/issues/form", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_issues_show_description_bottom hook" do
    context "with unsaved project" do
      should "render description_bottom partial without error" do
        @project = @unsaved_project
        @issue = Issue.new
        @issue.stubs(:project).returns(@unsaved_project)

        assert_nothing_raised do
          html = render(partial: "ai_helper/issues/subissues/description_bottom", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_issues_form_details_bottom hook" do
    context "with unsaved project" do
      should "render textarea_overlay partial without error" do
        @project = @unsaved_project
        @issue = Issue.new
        @issue.stubs(:project).returns(@unsaved_project)
        @issue.stubs(:persisted?).returns(false)
        @issue.stubs(:new_record?).returns(true)

        assert_nothing_raised do
          html = render(partial: "ai_helper/shared/textarea_overlay", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_layouts_base_sidebar hook (wiki summary)" do
    context "with unsaved project" do
      should "render wiki summary partial without error" do
        @project = @unsaved_project
        @page = nil
        @wiki = nil
        controller_name = "wiki"
        action_name = "show"

        assert_nothing_raised do
          html = render(partial: "ai_helper/wiki/summary", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_projects_show_right hook" do
    context "with unsaved project" do
      should "render health_report partial without error" do
        @project = @unsaved_project

        assert_nothing_raised do
          html = render(partial: "ai_helper/project/health_report", locals: { project: @unsaved_project })
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "view_layouts_base_body_bottom hook (wiki textarea)" do
    context "with unsaved project" do
      should "render wiki textarea_overlay partial without error" do
        @project = @unsaved_project
        @wiki = nil
        params = { controller: "wiki", action: "edit" }

        assert_nothing_raised do
          html = render(partial: "ai_helper/wiki/textarea_overlay", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "wiki typo_overlay partial" do
    context "with unsaved project" do
      should "render typo_overlay partial without error" do
        @project = @unsaved_project
        @wiki = nil
        params = { controller: "wiki", action: "edit" }

        assert_nothing_raised do
          html = render(partial: "ai_helper/wiki/typo_overlay", locals: {})
          # Should return empty string since project is unsaved
          assert_equal "", html
        end
      end
    end
  end

  context "stuff_todo_modal partial (rendered from html_header)" do
    context "with unsaved project" do
      should "render modal without error" do
        @project = @unsaved_project

        assert_nothing_raised do
          # This partial is rendered from html_header
          html = render(partial: "ai_helper/shared/stuff_todo_modal", locals: { project: @unsaved_project })
          # The modal may render, but with project=nil since unsaved
          assert_nothing_raised do
            html
          end
        end
      end
    end
  end
end
