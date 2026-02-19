# frozen_string_literal: true
require "redmine_ai_helper/base_tools"
require "redmine_ai_helper/util/attachment_file_helper"

module RedmineAiHelper
  module Tools
    # FileTools provides file analysis functions that internally call LLM
    # to describe and analyze file contents (images, PDFs, documents, code, audio, etc.).
    class FileTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::AttachmentFileHelper

      define_function :analyze_content_files,
        description: "Analyze files attached to a Redmine content (issue, wiki page, or forum message). " \
                     "Supports images, PDFs, documents, code files, and audio. " \
                     "Returns a text description/analysis of the file contents. " \
                     "Use this when you need to understand what is in attached files." do
        property :content_type, type: "string",
                 description: "The type of content: 'issue', 'wiki_page', or 'message'",
                 required: true, enum: ["issue", "wiki_page", "message"]
        property :content_id, type: "integer",
                 description: "The ID of the content", required: true
        property :question, type: "string",
                 description: "Optional question about the files. If not provided, a general description will be returned.",
                 required: false
      end

      # Analyze files attached to a Redmine content.
      # @param content_type [String] The type of content: 'issue', 'wiki_page', or 'message'
      # @param content_id [Integer] The ID of the content
      # @param question [String] Optional question about the files
      # @return [String] Text description/analysis of the file contents
      def analyze_content_files(content_type:, content_id:, question: nil)
        ai_helper_logger.debug(
          "analyze_content_files called: content_type=#{content_type}, " \
          "content_id=#{content_id}, question=#{question.inspect}"
        )
        container = resolve_container(content_type, content_id)
        ai_helper_logger.debug("resolved container: #{container.class.name}##{container.id}")
        file_paths = supported_attachment_paths(container)
        ai_helper_logger.debug(
          "file_paths: #{file_paths.size} files, " \
          "attachments count: #{container.respond_to?(:attachments) ? container.attachments.count : 'N/A'}"
        )
        raise("No supported file attachments found.") if file_paths.empty?

        prompt = build_analysis_prompt(question: question, file_count: file_paths.size)
        analyze_with_llm(prompt: prompt, file_paths: file_paths)
      end

      define_function :analyze_url_file,
        description: "Analyze a file from a URL (image, document, etc.). " \
                     "Returns a text description/analysis of the file content. " \
                     "Use this when you need to understand what is in a file referenced by URL." do
        property :url, type: "string",
                 description: "The URL of the file to analyze", required: true
        property :question, type: "string",
                 description: "Optional question about the file. If not provided, a general description will be returned.",
                 required: false
      end

      # Analyze a file from a URL.
      # @param url [String] The URL of the file to analyze
      # @param question [String] Optional question about the file
      # @return [String] Text description/analysis of the file content
      def analyze_url_file(url:, question: nil)
        prompt = build_analysis_prompt(question: question, file_count: 1)
        analyze_with_llm(prompt: prompt, file_paths: [url])
      end

      private

      # Resolve a container object from content_type and content_id.
      # @param content_type [String] The type of content
      # @param content_id [Integer] The ID of the content
      # @return [Issue, WikiPage, Message] The resolved container
      def resolve_container(content_type, content_id)
        ai_helper_logger.debug("resolve_container: content_type=#{content_type}, content_id=#{content_id}")
        case content_type
        when "issue"
          issue = Issue.find_by(id: content_id)
          raise("Issue not found: id = #{content_id}") if issue.nil? || !issue.visible?
          issue
        when "wiki_page"
          page = WikiPage.find_by(id: content_id)
          ai_helper_logger.debug("WikiPage.find_by(id: #{content_id}): #{page.inspect}")
          raise("Wiki page not found: id = #{content_id}") if page.nil? || !page.visible?
          page
        when "message"
          message = Message.find_by(id: content_id)
          raise("Message not found: id = #{content_id}") if message.nil? || !message.visible?
          message
        else
          raise("Unsupported content type: #{content_type}")
        end
      end

      # Build the analysis prompt.
      # @param question [String] Optional question about the files
      # @param file_count [Integer] Number of files
      # @return [String] The formatted prompt
      def build_analysis_prompt(question:, file_count:)
        prompt = load_prompt("file_tools/analyze")
        prompt.format(question: question || "", file_count: file_count.to_s)
      end

      # Call LLM to analyze files.
      # @param prompt [String] The analysis prompt
      # @param file_paths [Array<String>] Paths or URLs of files
      # @return [String] The analysis result text
      def analyze_with_llm(prompt:, file_paths:)
        llm_provider = RedmineAiHelper::LlmProvider.get_llm_provider
        instructions = load_prompt("file_tools/system_prompt").format
        chat = llm_provider.create_chat(instructions: instructions)
        response = chat.ask(prompt, with: file_paths)
        response.content
      end

      # Load a prompt template.
      # @param name [String] The template name
      # @return [PromptTemplate] The loaded template
      def load_prompt(name)
        RedmineAiHelper::Util::PromptLoader.load_template(name)
      end
    end
  end
end
