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

        save_or_raise!(page, "create wiki page")

        generate_wiki_data(page)
      end

      define_function :wiki_update_page, description: "Update an existing wiki page's content, title, and/or parent page.", write: true do
        property :project_id, type: "integer", description: "The project ID of the wiki.", required: true
        property :title, type: "string", description: "Current title of the page to update.", required: true
        property :content, type: "string", description: "New body text. Omit to leave content unchanged.", required: false
        property :new_title, type: "string", description: "New title for renaming. Omit to leave title unchanged.", required: false
        property :comment, type: "string", description: "Edit comment stored in version history.", required: false
        property :parent_title, type: "string", description: "Title of the new parent page. Pass an empty string to clear the parent (make top-level). Omit to leave the parent unchanged.", required: false
      end

      # Update an existing wiki page's content, title, and/or parent page.
      # @param project_id [Integer] The project ID.
      # @param title [String] Current title of the page to update.
      # @param content [String, nil] New body text. nil leaves content unchanged.
      # @param new_title [String, nil] New title for renaming. nil leaves title unchanged.
      # @param comment [String, nil] Optional edit comment.
      # @param parent_title [String, nil] Title of the new parent page. Empty string clears the parent (top-level). nil leaves the parent unchanged.
      # @return [Hash] The updated wiki page data.
      # @raise [RuntimeError] If any precondition fails.
      def wiki_update_page(project_id:, title:, content: nil, new_title: nil, comment: nil, parent_title: nil)
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
            save_or_raise!(page.content, "update wiki content")
          end

          unless new_title.nil?
            page.title = new_title
            save_or_raise!(page, "rename wiki page")
          end

          unless parent_title.nil?
            if parent_title.empty?
              page.parent = nil
            else
              parent_page = wiki.find_page(parent_title)
              raise "Parent page not found: title = #{parent_title}" unless parent_page
              if parent_page == page || parent_page.ancestors.include?(page)
                raise "Cannot set parent page: circular reference detected (title = #{parent_title})"
              end

              page.parent = parent_page
            end
            save_or_raise!(page, "update wiki page parent")
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

      private

      # Saves a wiki record or raises with its validation errors.
      # @param record [ActiveRecord::Base] The record to save (a WikiPage or WikiContent).
      # @param action [String] Short description of the action, used in the raised message.
      # @raise [RuntimeError] If the record fails to save.
      def save_or_raise!(record, action)
        return if record.save

        raise "Failed to #{action}: #{record.errors.full_messages.join(", ")}"
      end
    end
  end
end
