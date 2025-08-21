# frozen_string_literal: true
module RedmineAiHelper
  # Hook to display the chat screen in the sidebar
  class ViewHook < Redmine::Hook::ViewListener
    render_on :view_layouts_base_html_head, :partial => "ai_helper/html_header"
    render_on :view_layouts_base_body_top, :partial => "ai_helper/sidebar"
    render_on :view_issues_show_details_bottom, :partial => "ai_helper/issue_bottom"
    render_on :view_issues_edit_notes_bottom, :partial => "ai_helper/issue_form"
    render_on :view_issues_show_description_bottom, :partial => "ai_helper/subissue_gen/issue_description_bottom"
    render_on :view_issues_form_details_bottom, :partial => "ai_helper/textarea_overlay"
    render_on :view_layouts_base_sidebar, :partial => "ai_helper/wiki_summary"
    render_on :view_projects_show_right, :partial => "ai_helper/project_health"
  end
end
