# frozen_string_literal: true

require_dependency "projects_helper"

module RedmineAiHelper
  # Adds the AI Helper status icon to the project board.
  module ProjectsHelperPatch
    # Renders the project hierarchy and appends the AI Helper icon to
    # every project that has the ai_helper module enabled.
    # @param projects [Array<Project>] The projects to render
    # @return [String] The rendered HTML with AI Helper icons added
    def render_project_hierarchy(projects)
      # Call the original render_project_hierarchy method to get the base HTML
      html = render_project_hierarchy_without_ai_helper(projects)

      # Post-process the HTML to add AI Helper icons
      add_ai_helper_icons_to_project_hierarchy(html, projects)
    end

    private

    # Inserts the AI Helper icon into the rendered project hierarchy HTML.
    # @param html [String] The HTML rendered by the original helper
    # @param projects [Array<Project>] The projects contained in the HTML
    # @return [String] The HTML with AI Helper icons added
    def add_ai_helper_icons_to_project_hierarchy(html, projects)
      doc = Nokogiri::HTML::DocumentFragment.parse(html.to_s)

      projects.each do |project|
        next unless project.module_enabled?(:ai_helper)

        # Find the link to the project in the rendered HTML
        project_link = doc.search("a[href*='#{project_path(project)}']").first
        next unless project_link

        # Generate the icon HTML as a string
        icon_html_string = tag.span(
          sprite_icon("ai-helper-robot", l(:label_ai_helper), icon_only: true, plugin: :redmine_ai_helper),
          class: "icon-only icon-ai-helper-module"
        ).to_s

        # Parse the icon HTML string into a Nokogiri element
        icon_element = Nokogiri::HTML::DocumentFragment.parse(icon_html_string).first_element_child

        # Insert the icon as the last child of the project link's parent
        project_link.parent.add_child(icon_element)
      end

      doc.to_s.html_safe # rubocop:disable Rails/OutputSafety
    end
  end
end

unless ProjectsHelper.ancestors.include?(RedmineAiHelper::ProjectsHelperPatch)
  ProjectsHelper.alias_method :render_project_hierarchy_without_ai_helper, :render_project_hierarchy
  ProjectsHelper.prepend RedmineAiHelper::ProjectsHelperPatch
end
