require "langfuse"
$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/lib"
require "redmine_ai_helper/util/config_file"
require "redmine_ai_helper/user_patch"
require_dependency "redmine_ai_helper/view_hook"
Dir[File.join(File.dirname(__FILE__), "lib/redmine_ai_helper/agents", "*_agent.rb")].each do |file|
  require file
end

# Load MCP Server Loader and generate MCP Agent classes
require "redmine_ai_helper/util/mcp_server_loader"

# Generate MCP Agent classes after all agents are loaded
begin
  RedmineAiHelper::CustomLogger.instance.debug("Starting MCP Agent generation...")
  RedmineAiHelper::Util::McpServerLoader.load_all
  RedmineAiHelper::CustomLogger.instance.debug("MCP Agent generation completed")
rescue => e
  RedmineAiHelper::CustomLogger.instance.error("Error generating MCP Agent classes: #{e.message}")
  RedmineAiHelper::CustomLogger.instance.error(e.backtrace.join("\n"))
end
Redmine::Plugin.register :redmine_ai_helper do
  name "Redmine Ai Helper plugin"
  author "Haruyuki Iida"
  description "This plugin adds an AI assistant to Redmine."
  url "https://github.com/haru/redmine_ai_helper"
  author_url "https://github.com/haru"
  requires_redmine :version_or_higher => "6.0.0"

  version "1.14.0"

  project_module :ai_helper do
    permission :view_ai_helper,
               {
                 ai_helper: [
                   :chat, :chat_form, :reload, :clear, :call_llm,
                   :history, :issue_summary, :generate_issue_summary, :wiki_summary, :generate_wiki_summary, :conversation, :generate_issue_reply,
                   :generate_sub_issues, :add_sub_issues, :similar_issues, :check_duplicates, :project_health, :generate_project_health, :project_health_pdf, :project_health_markdown,
                   :project_health_metadata,
                   :suggest_completion, :suggest_wiki_completion, :check_typos,
                   :api_create_health_report, :suggest_assignees, :stuff_todo,
                 ],
                 ai_helper_dashboard: [
                   :index, :health_report_history, :health_report_show, :compare_health_reports, :comparison_pdf, :comparison_markdown,
                 ],
               }
    permission :settings_ai_helper,
               {
                 ai_helper_project_settings: [:show, :update],
               }, :require => :member
    permission :delete_ai_helper_health_reports,
               {
                 ai_helper_dashboard: [:health_report_destroy],
               }, :require => :member
  end

  menu :admin_menu, "icon ai_helper", {
         controller: "ai_helper_settings", action: "index",
       }, caption: :label_ai_helper, :icon => "ai-helper-robot",
          :plugin => :redmine_ai_helper

  menu :project_menu, :ai_helper_dashboard, {
         controller: "ai_helper_dashboard", action: "index",
       }, caption: :label_ai_helper

  # Add "To Do" menu item to account menu (appears near login info)
  # URL is "#" because the actual API call is handled by JavaScript via meta tag.
  # The link is hidden on non-project pages by JavaScript.
  menu :account_menu, :ai_helper_stuff_todo, "#",
       :caption => Proc.new { I18n.t("ai_helper.stuff_todo.menu_label") },
       :if => Proc.new {
         User.current.logged?
       },
       :first => true,
       :icon => "ai-helper-robot",
       :plugin => :redmine_ai_helper,
       :html => { id: "ai-helper-stuff-todo-link", style: "display:none;" }
end
