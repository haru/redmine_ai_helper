module RedmineAiHelper
  module Util
    # Helper module for extracting image attachment disk paths from Redmine containers.
    module AttachmentImageHelper
      # Returns disk paths of image attachments from a container.
      # @param container [Issue, WikiPage, Message] an object that responds to :attachments
      # @return [Array<String>] disk paths of existing image files
      def image_attachment_paths(container)
        return [] unless container.respond_to?(:attachments)

        container.attachments.select { |a| a.image? && File.exist?(a.diskfile) }
                             .map(&:diskfile)
      end
    end
  end
end
