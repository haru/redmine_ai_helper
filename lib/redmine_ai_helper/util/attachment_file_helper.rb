require "stringio"
require_relative "prompt_loader"

module RedmineAiHelper
  module Util
    # Helper module for extracting supported attachments from Redmine containers
    # as sources that RubyLLM can process (disk paths or in-memory attachments).
    # Supports images, audio, documents, and code files. Office documents that
    # Redmine can convert to Markdown (Redmine 7.0+ with Pandoc) are sent as the
    # Markdown text produced by Redmine's Markdown preview.
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
      # Markdown image syntax, e.g. ![alt](media/image1.png), in converted Office documents.
      MARKDOWN_IMAGE_PATTERN = /!\[[^\]]*\]\([^)]*\)/
      # HTML image tags, which Pandoc's documented GFM output uses for images with attributes
      # or captions (not checked against real Office documents; see research R-008).
      HTML_IMAGE_PATTERN = /<img\b[^>]*>/i
      # Image references removed before judging whether a converted document has text.
      IMAGE_REFERENCE_PATTERNS = [ MARKDOWN_IMAGE_PATTERN, HTML_IMAGE_PATTERN ].freeze
      # A UTF-8 character has at most 4 bytes, so a cut one leaves at most 3 stray bytes.
      MAX_INCOMPLETE_UTF8_BYTES = 3

      # Returns RubyLLM sources for the supported attachments of a container.
      # Text files that are not valid UTF-8 are converted using Redmine's
      # repositories_encodings setting; files that cannot be converted are replaced
      # by an attachment holding only a notice. Office documents that Redmine's Markdown
      # preview can convert are sent as in-memory Markdown attachments named
      # "<original filename>.md"; the document is never sent as the original binary file.
      # @param container [Issue, WikiPage, Message] an object that responds to :attachments
      # @return [Array<String, RubyLLM::Attachment>] disk paths, or attachments for converted text files and Office documents
      def supported_attachment_paths(container)
        return [] unless container.respond_to?(:attachments)
        return [] unless AiHelperSetting.attachment_send_enabled?

        max_size = AiHelperSetting.attachment_max_size_mb * 1.megabyte

        container.attachments
          .select { |a| (supported_file?(a) || office_document?(a)) && File.exist?(a.diskfile) && a.filesize <= max_size }
          .map { |a| llm_attachment_source(a) }
      end

      # Backward compatibility alias
      alias_method :image_attachment_paths, :supported_attachment_paths

      # Returns the file type category of an attachment.
      # Office documents that Redmine's Markdown preview can convert are "document".
      # @param attachment [Attachment] the attachment to classify
      # @return [String, nil] "image", "audio", "document", "code", or nil
      def attachment_file_type(attachment)
        ext = File.extname(attachment.filename).delete(".").downcase
        type = if IMAGE_EXTENSIONS.include?(ext)
          "image"
        elsif AUDIO_EXTENSIONS.include?(ext)
          "audio"
        elsif DOCUMENT_EXTENSIONS.include?(ext)
          "document"
        elsif SUPPORTED_EXTENSIONS.include?(ext)
          "code"
        end
        return type if type

        "document" if office_document?(attachment)
      end

      private

      # Returns what should be passed to RubyLLM for an attachment.
      # @param attachment [Attachment] an attachment that exists on disk and has a supported
      #   extension or is an Office document that Redmine can convert
      # @return [String, RubyLLM::Attachment] the disk path, an attachment with UTF-8 text,
      #   or an attachment with the Markdown of an Office document or its notice
      def llm_attachment_source(attachment)
        return office_document_source(attachment) if !supported_file?(attachment) && office_document?(attachment)
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
      # Office documents are also "document" and return true, so callers must send them
      # to office_document_source before calling this.
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
        RubyLLM::Attachment.new(StringIO.new(attachment_notice("unreadable_attachment", attachment)), filename: attachment.filename)
      end

      # Checks if Redmine's Markdown preview can convert an attachment. Redmine 6.x has no
      # such method, so attachments that do not respond to it are never Office documents.
      # @param attachment [Attachment] the attachment to check
      # @return [Boolean] true if Redmine reports that the attachment can be converted to Markdown
      def office_document?(attachment)
        attachment.respond_to?(:markdownized_previewable?) && attachment.markdownized_previewable?
      end

      # Builds the attachment for an Office document from Redmine's Markdown conversion.
      # Redmine returns nil when the conversion fails (Pandoc error, timeout, source too large),
      # in which case only a notice is sent.
      # @param attachment [Attachment] an Office document that Redmine can convert
      # @return [RubyLLM::Attachment] attachment with the Markdown text and notices, or with the notice only
      # @raise [EncodingError] if the converted text is not valid UTF-8 apart from a last character
      #   cut at the output limit
      # @raise [TypeError] if Redmine returns something other than a String or nil
      def office_document_source(attachment)
        bytes = attachment.markdownized_preview_content
        case bytes
        when nil
          office_unconvertible_placeholder(attachment)
        when String
          office_markdown_attachment(bytes, attachment)
        else
          raise TypeError, "Markdown preview of attachment ##{attachment.id} (#{attachment.filename}) returned #{bytes.class}, expected String or nil"
        end
      end

      # Builds the attachment holding the converted Markdown of an Office document and its notices.
      # The name gets a ".md" suffix so RubyLLM embeds the text instead of the binary file.
      # @param bytes [String] converted text read by Redmine as binary
      # @param attachment [Attachment] the Office document
      # @return [RubyLLM::Attachment] attachment with the Markdown text and notices
      # @raise [EncodingError] if the converted text is not valid UTF-8 apart from a last character
      #   cut at the output limit
      def office_markdown_attachment(bytes, attachment)
        truncated = bytes.bytesize >= Redmine::Markdownizer::MAX_OUTPUT_SIZE
        if truncated
          RedmineAiHelper::CustomLogger.instance.info(
            "[AttachmentFileHelper] Attachment ##{attachment.id} (#{attachment.filename}) reached the Markdown output limit; sending the truncated text"
          )
        end
        markdown = valid_utf8_prefix(bytes, attachment, truncated: truncated)
        text = [ markdown, *office_notices(markdown, attachment, truncated: truncated) ].join("\n\n")
        RubyLLM::Attachment.new(StringIO.new(text), filename: "#{attachment.filename}.md")
      end

      # Builds an attachment containing only a notice that an Office document could not be converted.
      # @param attachment [Attachment] the Office document
      # @return [RubyLLM::Attachment] attachment with the notice text and the Markdown filename
      def office_unconvertible_placeholder(attachment)
        RedmineAiHelper::CustomLogger.instance.warn(
          "[AttachmentFileHelper] Attachment ##{attachment.id} (#{attachment.filename}) could not be converted to Markdown; sending a notice instead"
        )
        RubyLLM::Attachment.new(
          StringIO.new(attachment_notice("office_unconvertible", attachment)),
          filename: "#{attachment.filename}.md"
        )
      end

      # Returns the bytes as UTF-8, removing the incomplete last character that Redmine's
      # byte-wise cut at the output limit can leave. Any other invalid byte is an error,
      # including an incomplete last character in a result that did not reach the limit.
      # @param bytes [String] converted text read by Redmine as binary
      # @param attachment [Attachment] the Office document, for the error message
      # @param truncated [Boolean] true if the result reached the output limit
      # @return [String] valid UTF-8 text
      # @raise [EncodingError] if the text is not valid UTF-8 after removing an incomplete
      #   last character of up to 3 bytes (only when truncated)
      def valid_utf8_prefix(bytes, attachment, truncated:)
        max_cut = truncated ? [ MAX_INCOMPLETE_UTF8_BYTES, bytes.bytesize ].min : 0
        (0..max_cut).each do |cut|
          tail = bytes.byteslice(bytes.bytesize - cut, cut).bytes
          next unless cut.zero? || incomplete_utf8_sequence?(tail)

          text = bytes.byteslice(0, bytes.bytesize - cut).force_encoding(Encoding::UTF_8)
          return text if text.valid_encoding?
        end
        raise EncodingError, "Markdown converted from attachment ##{attachment.id} (#{attachment.filename}) is not valid UTF-8"
      end

      # Checks if bytes are the start of a multibyte UTF-8 character that is cut short.
      # @param tail [Array<Integer>] the trailing bytes of the text
      # @return [Boolean] true if a lead byte is followed by fewer continuation bytes than it announces
      def incomplete_utf8_sequence?(tail)
        lead = tail.first
        expected = if lead.between?(0xC2, 0xDF) then 2
        elsif lead.between?(0xE0, 0xEF) then 3
        elsif lead.between?(0xF0, 0xF4) then 4
        end
        !expected.nil? && tail.size < expected && tail.drop(1).all? { |b| b.between?(0x80, 0xBF) }
      end

      # Builds the notices that follow the Markdown of an Office document, in a fixed order.
      # @param markdown [String] the converted Markdown
      # @param attachment [Attachment] the Office document
      # @param truncated [Boolean] true if the conversion result reached the output limit
      # @return [Array<String>] notice texts for truncation, omitted images and missing text
      def office_notices(markdown, attachment, truncated:)
        images = IMAGE_REFERENCE_PATTERNS.any? { |re| markdown.match?(re) }
        text_only = IMAGE_REFERENCE_PATTERNS.inject(markdown) { |text, re| text.gsub(re, "") }
        notices = []
        notices << attachment_notice("office_truncated", attachment) if truncated
        notices << attachment_notice("office_images_omitted", attachment) if images
        notices << attachment_notice("office_no_text", attachment) if text_only.strip.empty?
        notices
      end

      # Loads a notice template about an attachment.
      # @param name [String] template name under attachment_file_helper/
      # @param attachment [Attachment] the attachment the notice is about
      # @return [String] the notice with the original filename
      def attachment_notice(name, attachment)
        RedmineAiHelper::Util::PromptLoader
          .load_template("attachment_file_helper/#{name}")
          .format(filename: attachment.filename)
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
