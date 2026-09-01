# frozen_string_literal: true

module RedmineAiHelper
  # Hook to display the chat screen in the sidebar
  class ViewHook < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, partial: "ai_helper/shared/html_header"
    render_on :view_layouts_base_body_top, partial: "ai_helper/chat/sidebar"
    render_on :view_issues_show_details_bottom, partial: "ai_helper/issues/bottom"
    render_on :view_issues_edit_notes_bottom, partial: "ai_helper/issues/form"
    render_on :view_issues_show_description_bottom, partial: "ai_helper/issues/subissues/description_bottom"
    render_on :view_issues_form_details_bottom, partial: "ai_helper/shared/textarea_overlay"
    render_on :view_layouts_base_sidebar, partial: "ai_helper/wiki/summary"
    render_on :view_projects_show_right, partial: "ai_helper/project/health_report"
    # NOTE: render_on defines a method named after the hook, so multiple calls for the
    # same hook overwrite each other. All view_layouts_base_body_bottom partials must be
    # passed together in a single call.
    render_on :view_layouts_base_body_bottom,
              { partial: "ai_helper/wiki/textarea_overlay" },
              { partial: "ai_helper/shared/stuff_todo_modal_wrapper" },
              { partial: "ai_helper/project/index_legend" }
  end
end
