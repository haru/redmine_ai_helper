require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/util/wiki_json"

class RedmineAiHelper::Util::WikiJsonTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages, :wiki_contents, :users, :attachments

  context "generate_wiki_data" do
    setup do
      @project = Project.find(1)
      @wiki = @project.wiki
      @page = @wiki.pages.first
      attachment = Attachment.find(1)
      attachment.container = @page
      attachment.save!
      @page.reload
      @test_class = TestClass.new
    end

    should "generate correct wiki data" do
      wiki_data = @test_class.generate_wiki_data(@page)

      assert_equal @page.title, wiki_data[:title]
      assert_equal @page.text, wiki_data[:text]
      assert_equal @page.content.author.id, wiki_data[:author][:id]
      assert_equal @page.version, wiki_data[:version]
      assert wiki_data[:attachments].is_a?(Array)
      assert wiki_data[:attachments].length > 0
    end

    should "include type 'image' for image attachments" do
      Attachment.any_instance.stubs(:filename).returns("screenshot.png")

      wiki_data = @test_class.generate_wiki_data(@page)
      attachment_data = wiki_data[:attachments].first

      assert_equal "image", attachment_data[:type]
    end

    should "include type 'document' for document attachments" do
      Attachment.any_instance.stubs(:filename).returns("report.pdf")

      wiki_data = @test_class.generate_wiki_data(@page)
      attachment_data = wiki_data[:attachments].first

      assert_equal "document", attachment_data[:type]
    end

    should "include type 'code' for code attachments" do
      Attachment.any_instance.stubs(:filename).returns("script.rb")

      wiki_data = @test_class.generate_wiki_data(@page)
      attachment_data = wiki_data[:attachments].first

      assert_equal "code", attachment_data[:type]
    end

    should "include type 'audio' for audio attachments" do
      Attachment.any_instance.stubs(:filename).returns("recording.mp3")

      wiki_data = @test_class.generate_wiki_data(@page)
      attachment_data = wiki_data[:attachments].first

      assert_equal "audio", attachment_data[:type]
    end

    should "include type nil for unsupported attachments" do
      Attachment.any_instance.stubs(:filename).returns("archive.zip")

      wiki_data = @test_class.generate_wiki_data(@page)
      attachment_data = wiki_data[:attachments].first

      assert_nil attachment_data[:type]
    end

    should "not include disk_path in attachments" do
      wiki_data = @test_class.generate_wiki_data(@page)

      wiki_data[:attachments].each do |attachment_data|
        assert_not_includes attachment_data.keys, :disk_path,
          "Attachment data must not contain disk_path for security reasons"
      end
    end
  end

  class TestClass < RedmineAiHelper::BaseTools
    include RedmineAiHelper::Util::WikiJson
  end
end
