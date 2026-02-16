# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/wiki_json"
require "redmine_ai_helper/util/attachment_image_helper"

module RedmineAiHelper
  module Tools
    # WikiTools is a specialized tool for handling Redmine wiki-related queries.
    class WikiTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::WikiJson
      include RedmineAiHelper::Util::AttachmentImageHelper
      define_function :read_wiki_page, description: "Read a wiki page from the database. It includes the title, text, author, version, created_on, updated_on, children, parent, and attachments." do
        property :project_id, type: "integer", description: "The project ID of the wiki page to read.", required: true
        property :title, type: "string", description: "The title of the wiki page to read.", required: true
      end
      # Read an issue from the database.
      # @param project_id [Integer] The project ID of the wiki page to read.
      # @param title [String] The title of the wiki page to read.
      # @return [Hash] A hash containing wiki page information.
      def read_wiki_page(project_id:, title:)
        wiki = Wiki.find_by(project_id: project_id)
        raise("Wiki not found: project_id = #{project_id}") if !wiki || !wiki.visible?

        pages = wiki.pages
        ai_helper_logger.debug("Wiki pages: #{pages.inspect}")
        page = pages.find_by(title: title)
        raise("Page not found: title = #{title}") if !page || !page.visible?

        wiki_data = generate_wiki_data(page)
        image_paths = image_attachment_paths(page)

        if image_paths.any?
          RubyLLM::Content.new(JSON.pretty_generate(wiki_data), image_paths)
        else
          wiki_data
        end
      end

      define_function :list_wiki_pages, description: "List all wiki pages in the project. It includes the title, author, created_on, and updated_on." do
        property :project_id, type: "integer", description: "The project ID of the wiki pages to list.", required: true
      end
      # List all wiki pages in the project.
      # @param project_id [Integer] The project ID of the wiki pages to list.
      # @return [Array<Hash>] An array of hashes containing wiki page information.
      # @raise [RuntimeError] If the wiki is not found or not visible.
      def list_wiki_pages(project_id:)
        wiki = Wiki.find_by(project_id: project_id)
        raise("Wiki not found: project_id = #{project_id}") if !wiki || !wiki.visible?
        pages = wiki.pages.filter(&:visible?)
        json = pages.map do |page|
          {
            title: page.title,
            author: {
              id: page.content.author.id,
              name: page.content.author.name,
            },
            created_on: page.created_on,
            updated_on: page.updated_on,
          }
        end
        json
      end

      define_function :generate_url_for_wiki_page, description: "Generate a URL for a wiki page." do
        property :project_id, type: "integer", description: "The project ID of the wiki page to generate a URL for.", required: true
        property :title, type: "string", description: "The title of the wiki page to generate a URL for.", required: true
      end
      # Generate a URL for a wiki page.
      # @param project_id [Integer] The project ID of the wiki page to generate a URL for.
      # @param title [String] The title of the wiki page to generate a URL for.
      # @return [Hash] A hash containing the URL for the wiki page.
      def generate_url_for_wiki_page(project_id:, title:)
        wiki = Wiki.find_by(project_id: project_id)
        raise("Wiki not found: project_id = #{project_id}") if !wiki || !wiki.visible?
        page = wiki.pages.find_by(title: title)
        raise("Page not found: title = #{title}") if !page || !page.visible?
        url = "#{project_wiki_page_path(wiki.project, page.title)}"
        { url: url }
      end
    end
  end
end
