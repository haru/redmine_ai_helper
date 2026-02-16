require_relative "../../test_helper"

class WikiAgentTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages, :wiki_contents, :users

  def setup
    @project = projects(:projects_001)
    @wiki = wikis(:wikis_001)
    @wiki_page = wiki_pages(:wiki_pages_001)
    @user = users(:users_001)
    User.current = @user

    # Create a simple wiki content for testing
    @wiki_content = WikiContent.new(
      page: @wiki_page,
      text: "This is a test wiki page content for summarization.",
      author: @user,
      version: 1
    )
    @wiki_page.stubs(:content).returns(@wiki_content)
  end

  def teardown
    User.current = nil
  end

  context "WikiAgent" do
    setup do
      @agent = RedmineAiHelper::Agents::WikiAgent.new(project: @project)
    end

    should "have correct backstory" do
      assert_not_nil @agent.backstory
      assert @agent.backstory.is_a?(String)
    end

    should "have correct available_tool_classes" do
      tool_classes = @agent.available_tool_classes
      RedmineAiHelper::Tools::WikiTools.tool_classes.each do |tc|
        assert_includes tool_classes, tc
      end
    end

    should "include VectorTools when vector search is enabled" do
      AiHelperSetting.any_instance.stubs(:vector_search_enabled).returns(true)
      agent = RedmineAiHelper::Agents::WikiAgent.new(project: @project)
      tool_classes = agent.available_tool_classes
      RedmineAiHelper::Tools::VectorTools.tool_classes.each do |tc|
        assert_includes tool_classes, tc
      end
    end

    should "not include VectorTools when vector search is disabled" do
      AiHelperSetting.any_instance.stubs(:vector_search_enabled).returns(false)
      agent = RedmineAiHelper::Agents::WikiAgent.new(project: @project)
      tool_classes = agent.available_tool_classes
      RedmineAiHelper::Tools::VectorTools.tool_classes.each do |tc|
        assert_not_includes tool_classes, tc
      end
    end

    context "#wiki_summary" do
      setup do
        # Mock the prompt loading and formatting
        mock_prompt = mock('prompt')
        mock_prompt.stubs(:format).returns("Formatted prompt text")
        @agent.stubs(:load_prompt).returns(mock_prompt)

        # Mock the chat method to return a test summary
        @agent.stubs(:chat).returns("Test wiki summary")
      end

      should "generate summary for wiki page" do
        result = @agent.wiki_summary(wiki_page: @wiki_page)
        assert_equal "Test wiki summary", result
      end

      should "call load_prompt with correct template name" do
        @agent.expects(:load_prompt).with("wiki_agent/summary").returns(mock('prompt').tap do |p|
          p.stubs(:format).returns("Formatted text")
        end)
        @agent.wiki_summary(wiki_page: @wiki_page)
      end

      should "format prompt with wiki page data" do
        mock_prompt = mock('prompt')
        # Expect JSON data structure
        expected_data = {
          title: @wiki_page.title,
          content: @wiki_content.text
        }
        json_string = JSON.pretty_generate(expected_data)
        mock_prompt.expects(:format).with(wiki_data: json_string).returns("Formatted prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:chat).returns("Summary")

        @agent.wiki_summary(wiki_page: @wiki_page)
      end

      should "call chat with formatted message" do
        formatted_text = "Formatted prompt text"
        mock_prompt = mock('prompt')
        mock_prompt.stubs(:format).returns(formatted_text)
        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:image_attachment_paths).returns([])

        expected_messages = [{ role: "user", content: formatted_text }]
        @agent.expects(:chat).with(expected_messages, {}, nil, with: nil).returns("Summary")

        @agent.wiki_summary(wiki_page: @wiki_page)
      end

      should "pass image paths to chat with: parameter when images exist" do
        mock_prompt = mock('prompt')
        mock_prompt.stubs(:format).returns("Formatted prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)

        image_paths = ["/path/to/wiki_image.png"]
        @agent.stubs(:image_attachment_paths).with(@wiki_page).returns(image_paths)

        expected_messages = [{ role: "user", content: "Formatted prompt" }]
        @agent.expects(:chat).with(expected_messages, {}, nil, with: image_paths).returns("Summary with image")

        result = @agent.wiki_summary(wiki_page: @wiki_page)
        assert_equal "Summary with image", result
      end

      should "pass with: nil when no images exist" do
        mock_prompt = mock('prompt')
        mock_prompt.stubs(:format).returns("Formatted prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)

        @agent.stubs(:image_attachment_paths).with(@wiki_page).returns([])

        expected_messages = [{ role: "user", content: "Formatted prompt" }]
        @agent.expects(:chat).with(expected_messages, {}, nil, with: nil).returns("Summary without image")

        result = @agent.wiki_summary(wiki_page: @wiki_page)
        assert_equal "Summary without image", result
      end
    end

    context "#generate_wiki_completion" do
      setup do
        mock_prompt = mock('prompt')
        mock_prompt.stubs(:format).returns("Formatted completion prompt")
        @agent.stubs(:load_prompt).returns(mock_prompt)
        @agent.stubs(:chat).returns("completion text here")
      end

      should "return completion text" do
        completion = @agent.generate_wiki_completion(
          text: "This project focuses on",
          cursor_position: 21,
          project: @project,
          wiki_page: @wiki_page
        )

        assert completion.is_a?(String)
        assert completion.length > 0
      end

      should "handle new wiki page" do
        completion = @agent.generate_wiki_completion(
          text: "New page content",
          cursor_position: 16,
          project: @project,
          wiki_page: nil
        )

        assert completion.is_a?(String)
      end

      should "handle missing project" do
        completion = @agent.generate_wiki_completion(
          text: "Content without project",
          cursor_position: 23,
          project: nil,
          wiki_page: nil
        )

        assert completion.is_a?(String)
      end

      should "handle errors gracefully" do
        @agent.stubs(:chat).raises(StandardError.new("Test error"))

        completion = @agent.generate_wiki_completion(
          text: "Error test",
          cursor_position: 10,
          project: @project,
          wiki_page: @wiki_page
        )

        assert_equal "", completion
      end

      should "call load_prompt with correct template" do
        @agent.expects(:load_prompt).with("wiki_agent/wiki_inline_completion").returns(mock('prompt').tap do |p|
          p.stubs(:format).returns("Formatted text")
        end)

        @agent.generate_wiki_completion(
          text: "test text",
          cursor_position: 9,
          project: @project,
          wiki_page: @wiki_page
        )
      end
    end

    context "#build_wiki_completion_context" do
      should "include project and wiki info" do
        context = @agent.send(:build_wiki_completion_context, "test text", @project, @wiki_page)

        assert_equal @wiki_page.title, context[:page_title]
        assert_equal @project.name, context[:project_name]
        assert context.has_key?(:text_length)
      end

      should "handle nil wiki page" do
        context = @agent.send(:build_wiki_completion_context, "test text", @project, nil)

        assert_equal 'New Wiki Page', context[:page_title]
        assert_equal @project.name, context[:project_name]
      end

      should "handle nil project" do
        context = @agent.send(:build_wiki_completion_context, "test text", nil, @wiki_page)

        assert_equal @wiki_page.title, context[:page_title]
        assert_nil context[:project_name]
      end
    end

    context "#parse_wiki_completion_response" do
      should "clean and limit text" do
        long_text = "This is a very long response. " * 20
        cleaned = @agent.send(:parse_wiki_completion_response, long_text)

        assert cleaned.length <= 500
      end

      should "remove leading and trailing markers" do
        text_with_markers = "* Some completion text *"
        cleaned = @agent.send(:parse_wiki_completion_response, text_with_markers)

        assert_equal "Some completion text", cleaned
      end

      should "limit sentences" do
        many_sentences = "First sentence. Second sentence. Third sentence. Fourth sentence. Fifth sentence. Sixth sentence."
        cleaned = @agent.send(:parse_wiki_completion_response, many_sentences)

        sentences = cleaned.split(/[.!?。！？]\s*/)
        assert sentences.length <= 6
      end

      should "handle empty response" do
        cleaned = @agent.send(:parse_wiki_completion_response, "")
        assert_equal "", cleaned
      end
    end
  end
end
