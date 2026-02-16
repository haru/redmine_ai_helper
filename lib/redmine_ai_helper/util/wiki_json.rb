module RedmineAiHelper
  # Utility modules
  module Util
    # This module provides methods to generate JSON data for wiki pages.
    module WikiJson
      # Generates a JSON representation of a wiki page.
      # @param page [WikiPage] The wiki page to be represented in JSON.
      # @return [Hash] A hash representing the wiki page in JSON format.
      def generate_wiki_data(page)
        json = {
          title: page.title,
          text: page.text,
          page_url: project_wiki_page_path(page.wiki.project, page.title),
          author: {
            id: page.content.author.id,
            name: page.content.author.name,
          },
          version: page.version,
          created_on: page.created_on,
          updated_on: page.updated_on,
          children: page.children.filter(&:visible?).map do |child|
            {
              title: child.title,
            }
          end,
          parent: page.parent ? { title: page.parent.title } : nil,
          attachments: page.attachments.map do |attachment|
            {
              filename: attachment.filename,
              filesize: attachment.filesize,
              content_type: attachment.content_type,
              type: attachment.image? ? "image" : nil,
              description: attachment.description,
              created_on: attachment.created_on,
              attachment_url: attachment_path(attachment),
            }
          end,
        }
      end
    end
  end
end
