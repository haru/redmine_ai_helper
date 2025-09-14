# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html
RedmineApp::Application.routes.draw do
  post "projects/:id/ai_helper/chat", to: "ai_helper#chat", as: "ai_helper_chat"
  get "projects/:id/ai_helper/chat_form", to: "ai_helper#chat_form", as: "ai_helper_chat_form"
  get "projects/:id/ai_helper/reload", to: "ai_helper#reload", as: "ai_helper_reload"
  get "projects/:id/ai_helper/clear", to: "ai_helper#clear", as: "ai_helper_clear"
  get "projects/:id/ai_helper/history", to: "ai_helper#history", as: "ai_helper_history"
  get "projects/:id/ai_helper/conversation/:conversation_id", to: "ai_helper#conversation", as: "ai_helper_conversation"
  delete "projects/:id/ai_helper/conversation/:conversation_id", to: "ai_helper#conversation", as: "ai_helper_delete_conversation"
  post "projects/:id/ai_helper/call_llm", to: "ai_helper#call_llm", as: "ai_helper_call_llm"
  get "ai_helper/issue/:id/summary", to: "ai_helper#issue_summary", as: "ai_helper_issue_summary"
  post "ai_helper/issue/:id/generate_summary", to: "ai_helper#generate_issue_summary", as: "ai_helper_generate_issue_summary"
  get "ai_helper/wiki/:id/summary", to: "ai_helper#wiki_summary", as: "ai_helper_wiki_summary"
  post "ai_helper/wiki/:id/generate_summary", to: "ai_helper#generate_wiki_summary", as: "ai_helper_generate_wiki_summary"
  post "ai_helper/issue/:id/generate_reply", to: "ai_helper#generate_issue_reply", as: "ai_helper_generate_issue_reply"
  post "ai_helper/issue/:id/subissue_gen", to: "ai_helper#generate_sub_issues", as: "ai_helper_subissue_gen"
  post "ai_helper/issue/:id/add_sub_issues", to: "ai_helper#add_sub_issues", as: "ai_helper_add_sub_issues"
  get "ai_helper/issue/:id/similar_issues", to: "ai_helper#similar_issues", as: "ai_helper_similar_issues"
  post "projects/:id/ai_helper/issue/:issue_id/suggest_completion", to: "ai_helper#suggest_completion", as: "ai_helper_suggest_completion", constraints: { issue_id: /\d+|new/ }
  post "projects/:id/ai_helper/wiki/suggest_completion", to: "ai_helper#suggest_wiki_completion", as: "ai_helper_suggest_wiki_completion"
  post "projects/:id/ai_helper/wiki/:page_name/suggest_completion", to: "ai_helper#suggest_wiki_completion", as: "ai_helper_suggest_wiki_completion_with_page"
  get "projects/:id/ai_helper/project_health", to: "ai_helper#project_health", as: "ai_helper_project_health"
  get "projects/:id/ai_helper/generate_project_health", to: "ai_helper#generate_project_health", as: "ai_helper_generate_project_health"
  post "projects/:id/ai_helper/project_health_pdf", to: "ai_helper#project_health_pdf", as: "ai_helper_project_health_pdf"
  post "projects/:id/ai_helper/project_health_markdown", to: "ai_helper#project_health_markdown", as: "ai_helper_project_health_markdown"
  post "projects/:id/ai_helper/check_typos", to: "ai_helper#check_typos", as: "ai_helper_check_typos"

  get "ai_helper_settings/index", to: "ai_helper_settings#index", as: "ai_helper_setting"
  post "ai_helper_settings/index", to: "ai_helper_settings#update", as: "ai_helper_setting_update"

  get "ai_helper_model_profiles", to: "ai_helper_model_profiles#index", as: "ai_helper_model_profiles"
  get "ai_helper_model_profiles/:id", to: "ai_helper_model_profiles#show", as: "ai_helper_model_profiles_show"
  get "ai_helper_model_profiles/:id/edit", to: "ai_helper_model_profiles#edit", as: "ai_helper_model_profiles_edit"
  get "ai_helper_model_profiles_new", to: "ai_helper_model_profiles#new", as: "ai_helper_model_profiles_new"
  post "ai_helper_model_profiles", to: "ai_helper_model_profiles#create", as: "ai_helper_model_profiles_create"
  post "ai_helper_model_profiles/:id/edit", to: "ai_helper_model_profiles#update", as: "ai_helper_model_profiles_update"
  delete "ai_helper_model_profiles/:id", to: "ai_helper_model_profiles#destroy", as: "ai_helper_model_profiles_destroy"

  # get "ai_helper_project_settings/:id", to: "ai_helper_project_settings#show", as: "ai_helper_project_settings"
  patch "projects/:id/ai_helper_project_settings", to: "ai_helper_project_settings#update", as: "ai_helper_project_settings_update"

  get "projects/:id/ai_helper(/:tab)", to: "ai_helper_dashboard#index", as: "ai_helper_dashboard"
end
