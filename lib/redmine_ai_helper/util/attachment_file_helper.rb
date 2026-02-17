module RedmineAiHelper
  module Util
    # Helper module for extracting supported attachment file disk paths from Redmine containers.
    # Supports images, audio, documents, and code files that RubyLLM can process.
    module AttachmentFileHelper
      # File extensions supported by RubyLLM for multi-modal conversations
      SUPPORTED_EXTENSIONS = %w[
        jpg jpeg png gif webp bmp
        mp3 wav m4a ogg flac
        pdf txt md csv json xml
        rb py js html css ts tsx jsx
        java c cpp h hpp cs go rs
        sh bash zsh yml yaml toml
      ].freeze

      # Extension categories for file type classification
      IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp bmp].freeze
      AUDIO_EXTENSIONS = %w[mp3 wav m4a ogg flac].freeze
      DOCUMENT_EXTENSIONS = %w[pdf txt md csv json xml].freeze

      # Returns disk paths of supported attachments from a container.
      # @param container [Issue, WikiPage, Message] an object that responds to :attachments
      # @return [Array<String>] disk paths of existing supported files
      def supported_attachment_paths(container)
        return [] unless container.respond_to?(:attachments)

        container.attachments.select { |a| supported_file?(a) && File.exist?(a.diskfile) }
                             .map(&:diskfile)
      end

      # Backward compatibility alias
      alias_method :image_attachment_paths, :supported_attachment_paths

      # Returns the file type category of an attachment.
      # @param attachment [Attachment] the attachment to classify
      # @return [String, nil] "image", "audio", "document", "code", or nil
      def attachment_file_type(attachment)
        ext = File.extname(attachment.filename).delete(".").downcase
        if IMAGE_EXTENSIONS.include?(ext)
          "image"
        elsif AUDIO_EXTENSIONS.include?(ext)
          "audio"
        elsif DOCUMENT_EXTENSIONS.include?(ext)
          "document"
        elsif SUPPORTED_EXTENSIONS.include?(ext)
          "code"
        end
      end

      private

      # Checks if an attachment has a supported file extension.
      # @param attachment [Attachment] the attachment to check
      # @return [Boolean] true if the file extension is supported
      def supported_file?(attachment)
        ext = File.extname(attachment.filename).delete(".").downcase
        SUPPORTED_EXTENSIONS.include?(ext)
      end
    end
  end
end
