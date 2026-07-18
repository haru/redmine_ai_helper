# frozen_string_literal: true

require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/wiki_json"

module RedmineAiHelper
  module Tools
    # WikiWriteTools provides write operations for Redmine wiki pages:
    # create, update, and delete. All tools enforce ai_helper module
    # availability and wiki-specific permissions before making changes.
    class WikiWriteTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::WikiJson

      define_function :wiki_add_page, description: "Create a new wiki page in a project.", write: true do
        property :project_id, type: "integer", description: "The project ID of the wiki.", required: true
        property :title, type: "string", description: "Title of the new wiki page (must be unique within the wiki).", required: true
        property :content, type: "string", description: "Body text of the wiki page.", required: true
        property :parent_title, type: "string", description: "Title of the parent page. Creates a top-level page if omitted.", required: false
      end

      # Create a new wiki page in a project.
      # @param project_id [Integer] The project ID.
      # @param title [String] Title of the new wiki page.
      # @param content [String] Body text of the wiki page.
      # @param parent_title [String, nil] Optional parent page title.
      # @return [Hash] The created wiki page data.
      # @raise [RuntimeError] If any precondition fails.
      def wiki_add_page(project_id:, title:, content:, parent_title: nil)
        raise "project_id is required" if project_id.nil?
        raise "title is required" if title.nil?
        raise "content is required" if content.nil?

        project = Project.find_by(id: project_id)
        raise "Project not found. id = #{project_id}" unless project
        raise "ai_helper is not enabled for project: id = #{project_id}" unless accessible_project?(project)

        wiki = Wiki.find_by(project_id: project_id)
        raise "Wiki not found: project_id = #{project_id}" unless wiki

        raise "Permission denied" unless User.current.allowed_to?(:edit_wiki_pages, project)

        existing_page = wiki.find_page(title)
        raise "Wiki page already exists: title = #{title}" if existing_page

        parent_page = nil
        if parent_title
          parent_page = wiki.find_page(parent_title)
          raise "Parent page not found: title = #{parent_title}" unless parent_page
        end

        page = wiki.pages.build(title: title)
        page.parent = parent_page if parent_page

        wiki_content = WikiContent.new(
          text: content,
          author: User.current
        )
        page.content = wiki_content

        unless page.save
          raise "Failed to create wiki page: #{page.errors.full_messages.join(", ")}"
        end

        generate_wiki_data(page)
      end

      define_function :wiki_update_page, description: "Update an existing wiki page's content and/or title.", write: true do
        property :project_id, type: "integer", description: "The project ID of the wiki.", required: true
        property :title, type: "string", description: "Current title of the page to update.", required: true
        property :content, type: "string", description: "New body text. Omit to leave content unchanged.", required: false
        property :new_title, type: "string", description: "New title for renaming. Omit to leave title unchanged.", required: false
        property :comment, type: "string", description: "Edit comment stored in version history.", required: false
      end

      # Update an existing wiki page's content and/or title.
      # @param project_id [Integer] The project ID.
      # @param title [String] Current title of the page to update.
      # @param content [String, nil] New body text. nil leaves content unchanged.
      # @param new_title [String, nil] New title for renaming. nil leaves title unchanged.
      # @param comment [String, nil] Optional edit comment.
      # @return [Hash] The updated wiki page data.
      # @raise [RuntimeError] If any precondition fails.
      def wiki_update_page(project_id:, title:, content: nil, new_title: nil, comment: nil)
        raise "project_id is required" if project_id.nil?
        raise "title is required" if title.nil?

        project = Project.find_by(id: project_id)
        raise "Project not found. id = #{project_id}" unless project
        raise "ai_helper is not enabled for project: id = #{project_id}" unless accessible_project?(project)

        wiki = Wiki.find_by(project_id: project_id)
        raise "Wiki not found: project_id = #{project_id}" unless wiki

        raise "Permission denied" unless User.current.allowed_to?(:edit_wiki_pages, project)

        page = wiki.find_page(title)
        raise "Page not found: title = #{title}" unless page

        ActiveRecord::Base.transaction do
          unless content.nil?
            page.content.text = content
            page.content.author = User.current
            page.content.comments = comment unless comment.nil?
            unless page.content.save
              raise "Failed to update wiki content: #{page.content.errors.full_messages.join(", ")}"
            end
          end

          unless new_title.nil?
            page.title = new_title
            unless page.save
              raise "Failed to rename wiki page: #{page.errors.full_messages.join(", ")}"
            end
          end
        end

        page.reload
        generate_wiki_data(page)
      end

      define_function :wiki_delete_page, description: "Delete a wiki page and its associated content.", write: true do
        property :project_id, type: "integer", description: "The project ID of the wiki.", required: true
        property :title, type: "string", description: "Title of the page to delete.", required: true
      end

      # Delete a wiki page and its associated content.
      # @param project_id [Integer] The project ID.
      # @param title [String] Title of the page to delete.
      # @return [Hash] Confirmation with `{ deleted: true, title: }`.
      # @raise [RuntimeError] If any precondition fails.
      def wiki_delete_page(project_id:, title:)
        raise "project_id is required" if project_id.nil?
        raise "title is required" if title.nil?

        project = Project.find_by(id: project_id)
        raise "Project not found. id = #{project_id}" unless project
        raise "ai_helper is not enabled for project: id = #{project_id}" unless accessible_project?(project)

        wiki = Wiki.find_by(project_id: project_id)
        raise "Wiki not found: project_id = #{project_id}" unless wiki

        raise "Permission denied" unless User.current.allowed_to?(:delete_wiki_pages, project)

        page = wiki.find_page(title)
        raise "Page not found: title = #{title}" unless page

        page.destroy

        { deleted: true, title: title }
      end
    end
  end
end
