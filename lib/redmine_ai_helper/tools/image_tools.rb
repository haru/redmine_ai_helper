module RedmineAiHelper
  module Tools
    class ImageTools < RedmineAiHelper::BaseTools
      include RedmineAiHelper::Util::AttachmentImageHelper

      define_function :analyze_content_images,
        description: "Analyze images attached to a Redmine content (issue, wiki page, or forum message). " \
                     "Returns a text description of the image contents. " \
                     "Use this when you need to understand what is shown in attached images." do
        property :content_type, type: "string", description: "The type of content: 'issue', 'wiki_page', or 'message'", required: true, enum: ["issue", "wiki_page", "message"]
        property :content_id, type: "integer", description: "The ID of the content", required: true
        property :question, type: "string", description: "Optional question about the images. If not provided, a general description will be returned.", required: false
      end

      # Analyze images attached to a Redmine content.
      # @param content_type [String] The type of content: 'issue', 'wiki_page', or 'message'
      # @param content_id [Integer] The ID of the content
      # @param question [String] Optional question about the images
      # @return [String] Text description of the image contents
      def analyze_content_images(content_type:, content_id:, question: nil)
        container = resolve_container(content_type, content_id)
        image_paths = image_attachment_paths(container)
        raise("No image attachments found.") if image_paths.empty?

        prompt = build_analysis_prompt(question: question, image_count: image_paths.size)
        analyze_with_llm(prompt: prompt, image_paths: image_paths)
      end

      define_function :analyze_url_image,
        description: "Analyze an image from a URL. Returns a text description of the image content. " \
                     "Use this when you need to understand what is shown in an image referenced by URL." do
        property :url, type: "string", description: "The URL of the image to analyze", required: true
        property :question, type: "string", description: "Optional question about the image. If not provided, a general description will be returned.", required: false
      end

      # Analyze an image from a URL.
      # @param url [String] The URL of the image to analyze
      # @param question [String] Optional question about the image
      # @return [String] Text description of the image content
      def analyze_url_image(url:, question: nil)
        prompt = build_analysis_prompt(question: question, image_count: 1)
        analyze_with_llm(prompt: prompt, image_paths: [url])
      end

      private

      # Resolve a container object from content_type and content_id.
      # @param content_type [String] The type of content
      # @param content_id [Integer] The ID of the content
      # @return [Issue, WikiPage, Message] The resolved container
      def resolve_container(content_type, content_id)
        case content_type
        when "issue"
          issue = Issue.find_by(id: content_id)
          raise("Issue not found: id = #{content_id}") if issue.nil? || !issue.visible?
          issue
        when "wiki_page"
          page = WikiPage.find_by(id: content_id)
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
      # @param question [String] Optional question about the images
      # @param image_count [Integer] Number of images
      # @return [String] The formatted prompt
      def build_analysis_prompt(question:, image_count:)
        prompt = load_prompt("image_tools/analyze")
        prompt.format(question: question || "", image_count: image_count.to_s)
      end

      # Call LLM to analyze images.
      # @param prompt [String] The analysis prompt
      # @param image_paths [Array<String>] Paths or URLs of images
      # @return [String] The analysis result text
      def analyze_with_llm(prompt:, image_paths:)
        llm_provider = RedmineAiHelper::LlmProvider.get_llm_provider
        instructions = load_prompt("image_tools/system_prompt").format
        chat = llm_provider.create_chat(instructions: instructions)
        response = chat.ask(prompt, with: image_paths)
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
