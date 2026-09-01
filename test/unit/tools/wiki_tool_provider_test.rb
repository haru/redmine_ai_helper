require File.expand_path("../../../test_helper", __FILE__)

class WikiToolsTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages, :users, :enabled_modules

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

  def test_read_wiki_page_returns_parent_as_id_and_title_for_child_page
    child_page = @wiki.pages.find_by(title: "Page_with_an_inline_image")

    response = @provider.read_wiki_page(project_id: @project.id, title: child_page.title)

    assert_equal({ id: child_page.parent.id, title: child_page.parent.title }, response[:parent])
  end

  def test_list_wiki_pages
    response = @provider.list_wiki_pages(project_id: @project.id)

    assert_equal @wiki.pages.count, response.size
  end

  def test_list_wiki_pages_includes_own_id_for_each_element
    response = @provider.list_wiki_pages(project_id: @project.id)

    response.each do |element|
      page = @wiki.pages.find_by(title: element[:title])
      assert_equal page.id, element[:id]
    end
  end

  def test_list_wiki_pages_includes_parent_as_id_and_title_for_child_element
    response = @provider.list_wiki_pages(project_id: @project.id)
    child_page = @wiki.pages.find_by(title: "Page_with_an_inline_image")
    element = response.find { |e| e[:title] == child_page.title }

    assert_equal({ id: child_page.parent.id, title: child_page.parent.title }, element[:parent])
  end

  def test_list_wiki_pages_returns_nil_parent_for_top_level_element
    response = @provider.list_wiki_pages(project_id: @project.id)
    top_level_page = @wiki.pages.find_by(title: "CookBook_documentation")
    element = response.find { |e| e[:title] == top_level_page.title }

    assert_nil element[:parent]
  end

  def test_list_wiki_pages_raises_when_ai_helper_disabled_unchanged
    # ai_helper module disabled state does not affect list_wiki_pages, which only
    # checks wiki visibility; this asserts current wiki-not-found behavior is unchanged.
    EnabledModule.where(project_id: 3, name: "ai_helper").delete_all

    assert_raises(RuntimeError, "Wiki not found: project_id = 3") do
      @provider.list_wiki_pages(project_id: 3)
    end
  end

  def test_generate_url_for_wiki_page
    response = @provider.generate_url_for_wiki_page(project_id: @project.id, title: @page.title)
    expected_url = "/projects/#{@project.identifier}/wiki/#{@page.title}"

    assert_equal expected_url, response[:url]
  end

  context "read_wiki_page" do
    should "always return Hash regardless of image attachments" do
      response = @provider.read_wiki_page(project_id: @project.id, title: @page.title)

      assert_instance_of Hash, response
      assert_equal @page.title, response[:title]
    end
  end
end
