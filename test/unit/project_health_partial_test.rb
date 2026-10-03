require_relative "../test_helper"

class ProjectHealthPartialTest < ActionView::TestCase
  include ApplicationHelper
  include Rails.application.routes.url_helpers
  helper AiHelperDashboardHelper

  fixtures :projects, :users, :roles, :members, :member_roles, :enabled_modules

  setup do
    @project = projects(:projects_001)
    @project.enable_module!(:ai_helper)
    @user = users(:users_001)

    User.current = @user
    Rails.cache.clear
    AiHelperHealthReport.delete_all
  end

  teardown do
    User.current = nil
    Rails.cache.clear
  end

  should "render the latest stored health report when cache is empty" do
    report = AiHelperHealthReport.create!(
      project: @project,
      user: @user,
      health_report: "Stored health report content"
    )

    html = render(
      partial: "ai_helper/project/health_report",
      locals: { project: @project }
    )

    assert_includes html, "Stored health report content"
    assert_includes html, l(:field_created_on)
    assert_includes html, format_time(report.created_at)
    assert_includes html, ai_helper_project_health_metadata_path(@project)
    assert_includes html, 'meta name="ai-helper-project-health-created-label"'
  end

  should "export a stored report on the overview from the record-based endpoints" do
    report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: "Stored body")

    html = render(partial: "ai_helper/project/health_report", locals: { project: @project })

    assert_select Nokogiri::HTML::DocumentFragment.parse(html), "p.other-formats" do
      assert_select "a.text[href=?]", ai_helper_health_report_markdown_path(@project, report_id: report.id)
      assert_select "a.pdf[href=?]", ai_helper_health_report_show_path(@project, report_id: report.id, format: :pdf)
      assert_select "a#ai-helper-markdown-export-link, a#ai-helper-pdf-export-link", 0
    end
  end

  should "export an unsaved cached report on the overview through the body-posting endpoints" do
    # The test environment uses :null_store, so stub the overview's cache read
    Rails.cache.stubs(:read).with("project_health_#{@project.id}___").returns("Streamed body")

    html = render(partial: "ai_helper/project/health_report", locals: { project: @project })

    assert_select Nokogiri::HTML::DocumentFragment.parse(html), "p.other-formats" do
      assert_select "a#ai-helper-markdown-export-link[href=?]", ai_helper_project_health_markdown_path(@project)
      assert_select "a#ai-helper-pdf-export-link[href=?]", ai_helper_project_health_pdf_path(@project)
    end
  end

  context "detail pane and standalone page shared body partial" do
    setup do
      @report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "# Stored report\n\nBody text"
      )
    end

    should "render the shared body partial from the detail pane" do
      html = render(
        partial: "ai_helper/project/health_report_detail_pane",
        locals: { health_report: @report }
      )

      assert_body_partial_structure(html, @report)
    end

    should "render the shared body partial from the standalone show page" do
      @health_report = @report
      html = render(
        partial: "ai_helper/project/health_report_show",
        locals: { health_report: @report }
      )

      assert_body_partial_structure(html, @report)
    end

    should "render Markdown body regardless of the text formatting setting" do
      original_formatting = Setting.text_formatting
      Setting.text_formatting = "textile"

      html = render(
        partial: "ai_helper/project/health_report_detail_pane",
        locals: { health_report: @report }
      )

      Setting.text_formatting = original_formatting

      assert_includes html, "<h1>Stored report</h1>"
      assert_includes html, "<p>Body text</p>"
    end
  end

  context "history list rows" do
    setup do
      AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Report body",
        created_at: 2.days.ago
      )
      @health_reports = AiHelperHealthReport.sorted.to_a
      @health_report_count = @health_reports.size
      @health_report_pages = Redmine::Pagination::Paginator.new(@health_report_count, 25, nil)
      @selected_report = @health_reports.first
    end

    should "carry the detail URL and not embed the report content" do
      report = @health_reports.first

      html = render(partial: "ai_helper/project/health_report_history")

      assert_includes html, %(data-report-detail-url="#{ai_helper_health_report_show_path(@project, report_id: report.id)}")
      assert_not_includes html, "data-report-content"
    end
  end

  context "edit UI" do
    setup do
      @role = roles(:roles_001)
      @report = AiHelperHealthReport.create!(
        project: @project,
        user: @user,
        health_report: "Current body"
      )
    end

    teardown do
      @role.remove_permission! :edit_ai_helper_health_reports
    end

    should "render the edit link and edit form for an editable user" do
      @role.add_permission! :edit_ai_helper_health_reports
      User.current = users(:users_002)

      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })

      assert_edit_ui(html, @report)
    end

    should "render the edit UI for an administrator" do
      User.current = users(:users_001)

      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })

      assert_edit_ui(html, @report)
    end

    should "not render the edit link nor the edit form for a user without the permission" do
      User.current = users(:users_002)
      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })

      assert_not_includes html, "ai-helper-health-report-edit-link"
      assert_not_includes html, "ai-helper-health-report-edit-form"
      assert_not_includes html, "data-update-url"
    end
  end

  context "edited status display" do
    setup do
      @editor = users(:users_002)
      @report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: "AI body")
    end

    should "not render the edited notice nor the edited marker flag for an unedited report" do
      html = Nokogiri::HTML::DocumentFragment.parse(
        render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })
      )

      assert_select html, "p.ai-helper-health-report-edited-notice", 0
    end

    should "render the edited notice in the meta block before the view for an edited report" do
      @report.update_content("Edited body", @editor)
      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report.reload })

      doc = Nokogiri::HTML::DocumentFragment.parse(html)
      assert_select doc, "p.warning.ai-helper-health-report-edited-notice", 0
      assert_select doc, ".ai-helper-health-report-meta p.ai-helper-health-report-edited-notice strong",
                    text: "#{l("ai_helper.health_report_edit.edited")}:"
      assert_select doc, "p.ai-helper-health-report-edited-notice a[href=?]", "/users/#{@editor.id}"
      assert_includes html, format_time(@report.last_edited_on)
      assert_operator html.index("ai-helper-health-report-edited-notice"), :<, html.index("ai-helper-health-report-view")
    end

    should "link the Markdown export in other-formats" do
      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })

      assert_select Nokogiri::HTML::DocumentFragment.parse(html),
                    "p.other-formats a.text[href=?]", ai_helper_health_report_markdown_path(@project, report_id: @report.id)
    end

    context "history marker" do
      setup do
        @health_reports = [ @report ]
        @health_report_count = 1
        @health_report_pages = Redmine::Pagination::Paginator.new(1, 25, nil)
        @selected_report = @report
      end

      should "render the marker hidden for an unedited report" do
        doc = Nokogiri::HTML::DocumentFragment.parse(render(partial: "ai_helper/project/health_report_history"))

        assert_select doc, "span.ai-helper-health-report-edited-marker[hidden]", 1
      end

      should "render the marker visible for an edited report" do
        @report.update_content("Edited body", @editor)
        doc = Nokogiri::HTML::DocumentFragment.parse(render(partial: "ai_helper/project/health_report_history"))

        assert_select doc, "span.ai-helper-health-report-edited-marker", 1
        assert_select doc, "span.ai-helper-health-report-edited-marker[hidden]", 0
        assert_select doc, "td.created_on span.ai-helper-health-report-created-on span.ai-helper-health-report-edited-marker[title=?]",
                      l("ai_helper.health_report_edit.edited")
      end
    end

    should "render the edited notice on the project overview for an edited latest report" do
      @report.update_content("Edited body", @editor)
      html = render(partial: "ai_helper/project/health_report", locals: { project: @project })

      assert_includes html, "ai-helper-health-report-edited-notice"
    end
  end

  context "original content toggle" do
    setup do
      @report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: "# AI original")
    end

    should "render the original and toggle links for an edited report, even for viewers who cannot edit" do
      @report.update_content("Edited body", users(:users_002))
      User.current = users(:users_002)
      doc = Nokogiri::HTML::DocumentFragment.parse(
        render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report.reload })
      )

      assert_select doc, "div.ai-helper-health-report-original[hidden] p.warning", text: l("ai_helper.health_report_edit.original_notice")
      assert_select doc, "div.ai-helper-health-report-original[hidden] div.ai-helper-final-content h1", text: "AI original"
      assert_select doc, "a.ai-helper-health-report-show-original", 1
      assert_select doc, "a.ai-helper-health-report-show-current[hidden]", 1
      assert_select doc, "a.ai-helper-health-report-edit-link", 0
    end

    should "not render the original nor the toggle links for an unedited report" do
      doc = Nokogiri::HTML::DocumentFragment.parse(
        render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report })
      )

      assert_select doc, "div.ai-helper-health-report-original", 0
      assert_select doc, "a.ai-helper-health-report-show-original", 0
      assert_select doc, "a.ai-helper-health-report-show-current", 0
    end
  end

  context "view-only user" do
    setup do
      @report = AiHelperHealthReport.create!(project: @project, user: @user, health_report: "AI body")
      @report.update_content("Edited body", users(:users_002))
      User.current = users(:users_002)
    end

    should "see the edited status and original toggle but no edit controls" do
      html = render(partial: "ai_helper/project/health_report_body", locals: { health_report: @report.reload })

      assert_not_includes html, "ai-helper-health-report-edit-link"
      assert_not_includes html, "ai-helper-health-report-edit-form"
      assert_includes html, "ai-helper-health-report-edited-notice"
      assert_includes html, "ai-helper-health-report-show-original"
    end
  end

  private

  def assert_edit_ui(html, report)
    html = Nokogiri::HTML::DocumentFragment.parse(html)
    assert_select html, "div.ai-helper-health-report-body[data-update-url]", 1
    assert_select html, "div.contextual a.icon.icon-edit.ai-helper-health-report-edit-link", 1
    assert_select html, "form.ai-helper-health-report-edit-form[hidden][data-save-failed-message=?]",
                  l("ai_helper.health_report_edit.save_failed")
    assert_select html, "form div#errorExplanation.ai-helper-health-report-edit-errors[hidden]", 1
    assert_select html, %(form input[type="hidden"][name="health_report[lock_version]"]), 1
    assert_select html, %(textarea.wiki-edit#health_report_health_report_#{report.id}[name="health_report[health_report]"][data-preview-url][data-help-url]), text: /Current body/
    assert_select html, %(form input[type="submit"][value="#{l(:button_save)}"]), 1
    assert_select html, "form a.ai-helper-health-report-edit-cancel", 1
    textarea = html.at_css("textarea")
    assert_equal ai_helper_health_report_preview_path(@project), textarea["data-preview-url"]
    assert_equal help_wiki_syntax_path, textarea["data-help-url"]
  end

  def assert_body_partial_structure(html, report)
    assert_includes html, %(class="ai-helper-health-report-body")
    assert_includes html, %(data-report-id="#{report.id}")
    assert_includes html, %(data-show-url="#{ai_helper_health_report_show_path(@project, report_id: report.id)}")
    assert_includes html, %(class="ai-helper-health-report-meta")
    assert_includes html, %(class="ai-helper-health-report-view")
    assert_includes html, %(class="ai-helper-health-report-current ai-helper-final-content" id="ai-helper-project-health-result")
    assert_includes html, %(p class="other-formats")
    assert_includes html, ai_helper_health_report_show_path(@project, report_id: report.id, format: :pdf)
  end
end
