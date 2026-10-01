require "stringio"
require_relative "prompt_loader"

module RedmineAiHelper
  module Util
    # Helper module for extracting supported attachments from Redmine containers
    # as sources that RubyLLM can process (disk paths or in-memory attachments).
    # Supports images, audio, documents, and code files.
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
      # Supported audio file extensions for attachment processing.
      AUDIO_EXTENSIONS = %w[mp3 wav m4a ogg flac].freeze
      # Supported document file extensions for attachment processing.
      DOCUMENT_EXTENSIONS = %w[pdf txt md csv json xml].freeze

      # Returns RubyLLM sources for the supported attachments of a container.
      # Text files that are not valid UTF-8 are converted using Redmine's
      # repositories_encodings setting; files that cannot be converted are replaced
      # by an attachment holding only a notice.
      # @param container [Issue, WikiPage, Message] an object that responds to :attachments
      # @return [Array<String, RubyLLM::Attachment>] disk paths, or attachments for converted text files
      def supported_attachment_paths(container)
        return [] unless container.respond_to?(:attachments)
        return [] unless AiHelperSetting.attachment_send_enabled?

        max_size = AiHelperSetting.attachment_max_size_mb * 1.megabyte

        container.attachments
          .select { |a| supported_file?(a) && File.exist?(a.diskfile) && a.filesize <= max_size }
          .map { |a| llm_attachment_source(a) }
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

      # Returns what should be passed to RubyLLM for an attachment.
      # @param attachment [Attachment] a supported attachment that exists on disk
      # @return [String, RubyLLM::Attachment] the disk path, or an attachment with UTF-8 text
      def llm_attachment_source(attachment)
        return attachment.diskfile unless text_attachment?(attachment)

        bytes = File.binread(attachment.diskfile)
        return attachment.diskfile if bytes.force_encoding(Encoding::UTF_8).valid_encoding?

        utf8 = convert_to_utf8(bytes)
        return unreadable_attachment_placeholder(attachment) if utf8.nil?

        RubyLLM::Attachment.new(StringIO.new(utf8), filename: attachment.filename)
      end

      # Converts bytes to UTF-8 using the encodings of Redmine's repositories_encodings
      # setting, tried in the configured order.
      # @param bytes [String] raw file content
      # @return [String, nil] UTF-8 text, or nil if no candidate encoding works
      def convert_to_utf8(bytes)
        Setting.repositories_encodings.to_s.split(",").map(&:strip).compact_blank.each do |name|
          converted = bytes.dup.force_encoding(name).encode(Encoding::UTF_8)
          return converted if converted.valid_encoding?
        rescue EncodingError, ArgumentError => e
          RedmineAiHelper::CustomLogger.instance.debug(
            "[AttachmentFileHelper] Skipping encoding #{name.inspect}: #{e.message}"
          )
          next
        end
        nil
      end

      # Checks if an attachment is a text file whose content is embedded as text.
      # @param attachment [Attachment] the attachment to check
      # @return [Boolean] true for document and code files other than PDF
      def text_attachment?(attachment)
        ext = File.extname(attachment.filename).delete(".").downcase
        %w[document code].include?(attachment_file_type(attachment)) && ext != "pdf"
      end

      # Builds an attachment containing only a notice that the file could not be read.
      # @param attachment [Attachment] the unreadable attachment
      # @return [RubyLLM::Attachment] attachment with the notice text and the original filename
      def unreadable_attachment_placeholder(attachment)
        RedmineAiHelper::CustomLogger.instance.warn(
          "[AttachmentFileHelper] Attachment ##{attachment.id} (#{attachment.filename}) could not be converted to UTF-8; sending a notice instead"
        )
        notice = RedmineAiHelper::Util::PromptLoader
          .load_template("attachment_file_helper/unreadable_attachment")
          .format(filename: attachment.filename)
        RubyLLM::Attachment.new(StringIO.new(notice), filename: attachment.filename)
      end

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
