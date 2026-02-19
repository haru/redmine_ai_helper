require File.expand_path("../../../test_helper", __FILE__)

class FileToolsTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :issue_statuses, :trackers, :enumerations, :users, :issue_categories, :versions, :custom_fields, :boards, :messages, :wikis, :wiki_pages, :wiki_contents

  def setup
    @provider = RedmineAiHelper::Tools::FileTools.new
    @issue = Issue.find(1)
    @project = Project.find(1)
    @board = @project.boards.first
    @message = @board.messages.first
    @wiki = @project.wiki
    @wiki_page = @wiki.pages.first

    # Mock LLM provider and chat
    @mock_chat = mock("chat")
    @mock_response = mock("response")
    @mock_response.stubs(:content).returns("This file contains a report with key findings.")
    @mock_chat.stubs(:ask).returns(@mock_response)

    @mock_llm_provider = mock("llm_provider")
    @mock_llm_provider.stubs(:create_chat).returns(@mock_chat)
    RedmineAiHelper::LlmProvider.stubs(:get_llm_provider).returns(@mock_llm_provider)
  end

  context "analyze_content_files" do
    context "with issue" do
      setup do
        @file_path = File.join(Dir.tmpdir, "test_file_tools.png")
        File.write(@file_path, "fake png content")
      end

      teardown do
        File.delete(@file_path) if File.exist?(@file_path)
      end

      should "analyze files attached to an issue" do
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([@file_path])

        result = @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
        assert_equal "This file contains a report with key findings.", result
      end

      should "analyze PDF files attached to an issue" do
        pdf_path = File.join(Dir.tmpdir, "test_report.pdf")
        File.write(pdf_path, "fake pdf content")
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([pdf_path])

        result = @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
        assert_equal "This file contains a report with key findings.", result
      ensure
        File.delete(pdf_path) if pdf_path && File.exist?(pdf_path)
      end

      should "pass question to LLM when provided" do
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([@file_path])

        @mock_chat.expects(:ask).with do |prompt, **kwargs|
          prompt.include?("What does this document describe?") && kwargs[:with] == [@file_path]
        end.returns(@mock_response)

        result = @provider.analyze_content_files(
          content_type: "issue",
          content_id: @issue.id,
          question: "What does this document describe?"
        )

        assert_instance_of String, result
      end

      should "return general description without question" do
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([@file_path])

        @mock_chat.expects(:ask).with do |prompt, **kwargs|
          kwargs[:with] == [@file_path]
        end.returns(@mock_response)

        result = @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
      end

      should "raise error when no supported files attached" do
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([])

        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)
        end
        assert_equal "No supported file attachments found.", error.message
      end

      should "not include disk path in return value" do
        @provider.stubs(:supported_attachment_paths).with(@issue).returns([@file_path])

        result = @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)

        assert_instance_of String, result
        refute_includes result, @file_path,
          "Return value must not contain disk path for security reasons"
        refute_includes result, Dir.tmpdir,
          "Return value must not contain any directory path"
      end
    end

    context "with wiki_page" do
      setup do
        @file_path = File.join(Dir.tmpdir, "test_wiki_file.pdf")
        File.write(@file_path, "fake pdf content")
      end

      teardown do
        File.delete(@file_path) if File.exist?(@file_path)
      end

      should "analyze files attached to a wiki page" do
        @provider.stubs(:supported_attachment_paths).with(@wiki_page).returns([@file_path])

        result = @provider.analyze_content_files(content_type: "wiki_page", content_id: @wiki_page.id)

        assert_instance_of String, result
        assert_equal "This file contains a report with key findings.", result
      end
    end

    context "with message" do
      setup do
        @file_path = File.join(Dir.tmpdir, "test_message_file.txt")
        File.write(@file_path, "fake text content")
      end

      teardown do
        File.delete(@file_path) if File.exist?(@file_path)
      end

      should "analyze files attached to a message" do
        @provider.stubs(:supported_attachment_paths).with(@message).returns([@file_path])

        result = @provider.analyze_content_files(content_type: "message", content_id: @message.id)

        assert_instance_of String, result
        assert_equal "This file contains a report with key findings.", result
      end
    end

    context "error handling" do
      should "raise error for non-existent issue" do
        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "issue", content_id: 999999)
        end
        assert_match(/Issue not found/, error.message)
      end

      should "raise error for non-existent wiki page" do
        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "wiki_page", content_id: 999999)
        end
        assert_match(/Wiki page not found/, error.message)
      end

      should "raise error for non-existent message" do
        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "message", content_id: 999999)
        end
        assert_match(/Message not found/, error.message)
      end

      should "raise error for unsupported content_type" do
        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "document", content_id: 1)
        end
        assert_match(/Unsupported content type/, error.message)
      end

      should "raise error for invisible issue" do
        Issue.any_instance.stubs(:visible?).returns(false)

        error = assert_raises(RuntimeError) do
          @provider.analyze_content_files(content_type: "issue", content_id: @issue.id)
        end
        assert_match(/Issue not found/, error.message)
      end
    end
  end

  context "analyze_url_file" do
    should "analyze file from URL" do
      url = "https://example.com/document.pdf"

      @mock_chat.expects(:ask).with do |prompt, **kwargs|
        kwargs[:with] == [url]
      end.returns(@mock_response)

      result = @provider.analyze_url_file(url: url)

      assert_instance_of String, result
      assert_equal "This file contains a report with key findings.", result
    end

    should "pass question to LLM when analyzing URL file" do
      url = "https://example.com/chart.png"

      @mock_chat.expects(:ask).with do |prompt, **kwargs|
        prompt.include?("What trend does this chart show?") && kwargs[:with] == [url]
      end.returns(@mock_response)

      result = @provider.analyze_url_file(url: url, question: "What trend does this chart show?")

      assert_instance_of String, result
    end
  end

  context "tool_classes" do
    should "have analyze_content_files tool" do
      tool_names = RedmineAiHelper::Tools::FileTools.tool_classes.map(&:name)
      assert tool_names.any? { |name| name.include?("AnalyzeContentFiles") },
        "FileTools should have analyze_content_files tool"
    end

    should "have analyze_url_file tool" do
      tool_names = RedmineAiHelper::Tools::FileTools.tool_classes.map(&:name)
      assert tool_names.any? { |name| name.include?("AnalyzeUrlFile") },
        "FileTools should have analyze_url_file tool"
    end
  end
end
