require File.expand_path("../../../test_helper", __FILE__)

class ImageToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :boards, :messages, :wikis, :wiki_pages, :wiki_contents

  def setup
    @provider = RedmineAiHelper::Tools::ImageTools.new
    @issue = Issue.find(1)
    @project = Project.find(1)
    @board = @project.boards.first
    @message = @board.messages.first
    @wiki = @project.wiki
    @wiki_page = @wiki.pages.first

    # Mock LLM provider and chat
    @mock_chat = mock("chat")
    @mock_response = mock("response")
    @mock_response.stubs(:content).returns("This image shows a screenshot of a web application.")
    @mock_chat.stubs(:ask).returns(@mock_response)

    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:create_chat).returns(@mock_chat)
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)
  end

  context "analyze_content_images" do
    context "with issue" do
      setup do
        @image_path = File.join(Dir.tmpdir, "test_image_tools.png")
        File.write(@image_path, "fake png content")
      end

      teardown do
        File.delete(@image_path) if File.exist?(@image_path)
      end

      should "analyze images attached to an issue" do
        @provider.stubs(:image_attachment_paths).with(@issue).returns([@image_path])

        result = @provider.analyze_content_images(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
        assert_equal "This image shows a screenshot of a web application.", result
      end

      should "pass question to LLM when provided" do
        @provider.stubs(:image_attachment_paths).with(@issue).returns([@image_path])

        @mock_chat.expects(:ask).with do |prompt, **kwargs|
          prompt.include?("What color is the button?") && kwargs[:with] == [@image_path]
        end.returns(@mock_response)

        result = @provider.analyze_content_images(
          content_type: "issue",
          content_id: @issue.id,
          question: "What color is the button?"
        )

        assert_instance_of String, result
      end

      should "return general description without question" do
        @provider.stubs(:image_attachment_paths).with(@issue).returns([@image_path])

        @mock_chat.expects(:ask).with do |prompt, **kwargs|
          kwargs[:with] == [@image_path]
        end.returns(@mock_response)

        result = @provider.analyze_content_images(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
      end

      should "raise error when no images attached" do
        @provider.stubs(:image_attachment_paths).with(@issue).returns([])

        assert_raises(RuntimeError, "No image attachments found.") do
          @provider.analyze_content_images(content_type: "issue", content_id: @issue.id)
        end
      end

      should "not include disk path in return value" do
        @provider.stubs(:image_attachment_paths).with(@issue).returns([@image_path])

        result = @provider.analyze_content_images(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
        refute_includes result, @image_path,
          "Return value must not contain disk path for security reasons"
        refute_includes result, Dir.tmpdir,
          "Return value must not contain any directory path"
      end
    end

    context "with wiki_page" do
      setup do
        @image_path = File.join(Dir.tmpdir, "test_wiki_image.png")
        File.write(@image_path, "fake png content")
      end

      teardown do
        File.delete(@image_path) if File.exist?(@image_path)
      end

      should "analyze images attached to a wiki page" do
        @provider.stubs(:image_attachment_paths).with(@wiki_page).returns([@image_path])

        result = @provider.analyze_content_images(content_type: "wiki_page", content_id: @wiki_page.id)

        assert_instance_of String, result
        assert_equal "This image shows a screenshot of a web application.", result
      end
    end

    context "with message" do
      setup do
        @image_path = File.join(Dir.tmpdir, "test_message_image.png")
        File.write(@image_path, "fake png content")
      end

      teardown do
        File.delete(@image_path) if File.exist?(@image_path)
      end

      should "analyze images attached to a message" do
        @provider.stubs(:image_attachment_paths).with(@message).returns([@image_path])

        result = @provider.analyze_content_images(content_type: "message", content_id: @message.id)

        assert_instance_of String, result
        assert_equal "This image shows a screenshot of a web application.", result
      end
    end

    context "error handling" do
      should "raise error for non-existent issue" do
        assert_raises(RuntimeError, "Issue not found") do
          @provider.analyze_content_images(content_type: "issue", content_id: 999999)
        end
      end

      should "raise error for non-existent wiki page" do
        assert_raises(RuntimeError, "Wiki page not found") do
          @provider.analyze_content_images(content_type: "wiki_page", content_id: 999999)
        end
      end

      should "raise error for non-existent message" do
        assert_raises(RuntimeError, "Message not found") do
          @provider.analyze_content_images(content_type: "message", content_id: 999999)
        end
      end

      should "raise error for unsupported content_type" do
        assert_raises(RuntimeError, "Unsupported content type") do
          @provider.analyze_content_images(content_type: "document", content_id: 1)
        end
      end

      should "raise error for invisible issue" do
        issue = Issue.find(1)
        Issue.any_instance.stubs(:visible?).returns(false)

        assert_raises(RuntimeError, "Issue not found") do
          @provider.analyze_content_images(content_type: "issue", content_id: issue.id)
        end
      end
    end
  end

  context "analyze_url_image" do
    should "analyze image from URL" do
      url = "https://example.com/image.png"

      @mock_chat.expects(:ask).with do |prompt, **kwargs|
        kwargs[:with] == [url]
      end.returns(@mock_response)

      result = @provider.analyze_url_image(url: url)

      assert_instance_of String, result
      assert_equal "This image shows a screenshot of a web application.", result
    end

    should "pass question to LLM when analyzing URL image" do
      url = "https://example.com/chart.png"

      @mock_chat.expects(:ask).with do |prompt, **kwargs|
        prompt.include?("What trend does this chart show?") && kwargs[:with] == [url]
      end.returns(@mock_response)

      result = @provider.analyze_url_image(url: url, question: "What trend does this chart show?")

      assert_instance_of String, result
    end
  end

  context "tool_classes" do
    should "have analyze_content_images tool" do
      tool_names = RedmineAiHelper::Tools::ImageTools.tool_classes.map(&:name)
      assert tool_names.any? { |name| name.include?("AnalyzeContentImages") },
        "ImageTools should have analyze_content_images tool"
    end

    should "have analyze_url_image tool" do
      tool_names = RedmineAiHelper::Tools::ImageTools.tool_classes.map(&:name)
      assert tool_names.any? { |name| name.include?("AnalyzeUrlImage") },
        "ImageTools should have analyze_url_image tool"
    end
  end
end
