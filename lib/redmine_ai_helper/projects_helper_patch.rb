# frozen_string_literal: true

require_dependency "projects_helper"

module RedmineAiHelper
  # Adds the AI Helper status icon to the project board.
  module ProjectsHelperPatch
    def render_project_hierarchy(projects)
      bookmarked_project_ids = User.current.bookmarked_project_ids
      render_project_nested_lists(projects) do |project|
        classes = project.css_classes.split
        classes += %w(icon icon-user my-project) if User.current.member_of?(project)
        classes += %w(icon icon-bookmarked-project) if bookmarked_project_ids.include?(project.id)

        s = link_to_project(project, {}, class: classes.uniq.join(' '))
        s << tag.span(sprite_icon('user', l(:label_my_projects), icon_only: true), class: 'icon-only icon-user my-project') if User.current.member_of?(project)
        s << tag.span(sprite_icon('bookmarked', l(:label_my_bookmarks), icon_only: true), class: 'icon-only icon-bookmarked-project') if bookmarked_project_ids.include?(project.id)
        if project.module_enabled?(:ai_helper)
          s << tag.span(
            sprite_icon('ai-helper-robot', l(:label_ai_helper), icon_only: true, plugin: :redmine_ai_helper),
            class: 'icon-only icon-ai-helper-module'
          )
        end
        if project.description.present?
          s << content_tag('div', textilizable(project, :short_description, :project => project), class: 'wiki description')
        end
        s
      end
    end
  end
end

unless ProjectsHelper.ancestors.include?(RedmineAiHelper::ProjectsHelperPatch)
  ProjectsHelper.prepend RedmineAiHelper::ProjectsHelperPatch
end
