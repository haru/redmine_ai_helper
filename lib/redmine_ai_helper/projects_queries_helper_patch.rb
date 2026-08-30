# frozen_string_literal: true

require_dependency "projects_queries_helper"

module RedmineAiHelper
  # Adds the AI Helper status icon to the project list.
  module ProjectsQueriesHelperPatch
    def column_value(column, item, value)
      return super unless item.is_a?(Project) && column.name == :name

      column_html = super
      return column_html unless item.module_enabled?(:ai_helper)

      column_html +
        tag.span(
          sprite_icon("ai-helper-robot", l(:label_ai_helper), icon_only: true, plugin: :redmine_ai_helper),
          class: "icon-only icon-ai-helper-module"
        )
    end
  end
end

unless ProjectsQueriesHelper.ancestors.include?(RedmineAiHelper::ProjectsQueriesHelperPatch)
  ProjectsQueriesHelper.prepend RedmineAiHelper::ProjectsQueriesHelperPatch
end
