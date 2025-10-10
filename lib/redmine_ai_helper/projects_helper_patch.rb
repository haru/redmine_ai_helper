# frozen_string_literal: true
require_dependency "projects_helper"

module RedmineAiHelper
  # Patch for ProjectsHelper to add AI Helper project settings tab
  module ProjectsHelperPatch
    # Add AI Helper settings tab to project settings
    # @return [Array<Hash>] Modified tabs array
    def project_settings_tabs
      tabs = super
      action = { :name => "ai_helper", :controller => "ai_helper_project_settings", :action => :show, :partial => "ai_helper_project_settings/show", :label => :label_ai_helper }

      tabs << action if User.current.allowed_to?(action, @project)

      tabs
    end
  end
end

ProjectsHelper.prepend(RedmineAiHelper::ProjectsHelperPatch)
