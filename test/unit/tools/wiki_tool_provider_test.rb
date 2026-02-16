require File.expand_path("../../../test_helper", __FILE__)

class WikiToolsTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages, :users

  def setup
    @provider = RedmineAiHelper::Tools::WikiTools.new
    @project = Project.find(1)
    @wiki = @project.wiki
    @page = @wiki.pages.first
  end

  def test_read_wiki_page_success
    response = @provider.read_wiki_page(project_id: @project.id, title: @page.title)
    assert_equal @page.title, response[:title]
  end

  def test_read_wiki_page_not_found
    assert_raises(RuntimeError, "Page not found: title = Nonexistent Page") do
      @provider.read_wiki_page(project_id: @project.id, title: "Nonexistent Page")
    end
  end

  def test_list_wiki_pages
    response = @provider.list_wiki_pages(project_id: @project.id)
    assert_equal @wiki.pages.count, response.size
  end

  def test_generate_url_for_wiki_page
    response = @provider.generate_url_for_wiki_page(project_id: @project.id, title: @page.title)
    expected_url = "/projects/#{@project.identifier}/wiki/#{@page.title}"
    assert_equal expected_url, response[:url]
  end

  context "read_wiki_page with image attachments" do
    should "return RubyLLM::Content when page has image attachments" do
      image_path = File.join(Dir.tmpdir, "test_wiki_image.png")
      File.write(image_path, "fake png content")
      @provider.stubs(:image_attachment_paths).returns([image_path])

      response = @provider.read_wiki_page(project_id: @project.id, title: @page.title)

      assert_instance_of RubyLLM::Content, response
      assert_includes response.text, @page.title
      assert_equal 1, response.attachments.size
    ensure
      File.delete(image_path) if File.exist?(image_path)
    end

    should "return Hash when page has no image attachments" do
      @provider.stubs(:image_attachment_paths).returns([])

      response = @provider.read_wiki_page(project_id: @project.id, title: @page.title)

      assert_instance_of Hash, response
      assert_equal @page.title, response[:title]
    end
  end
end
