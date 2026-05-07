require_relative "../test_helper"

class AiHelperSummaryCacheTest < ActiveSupport::TestCase
  fixtures :projects, :issues, :wikis, :wiki_pages, :wiki_contents

  def setup
    @issue = issues(:issues_001)
    @wiki_page = wiki_pages(:wiki_pages_001)
    @test_content = "This is a test summary content"
  end

  context "Issue cache methods" do
    should "find existing issue cache" do
      cache = AiHelperSummaryCache.create!(
        object_class: "Issue",
        object_id: @issue.id,
        content: @test_content
      )
      
      found_cache = AiHelperSummaryCache.issue_cache(issue_id: @issue.id)
      assert_equal cache.id, found_cache.id
      assert_equal @test_content, found_cache.content
    end

    should "return nil when no issue cache exists" do
      found_cache = AiHelperSummaryCache.issue_cache(issue_id: 999999)
      assert_nil found_cache
    end

    should "create new issue cache when none exists" do
      cache = AiHelperSummaryCache.update_issue_cache(
        issue_id: @issue.id,
        content: @test_content
      )
      
      assert_not_nil cache
      assert_equal "Issue", cache.object_class
      assert_equal @issue.id, cache.object_id
      assert_equal @test_content, cache.content
    end

    should "update existing issue cache" do
      existing_cache = AiHelperSummaryCache.create!(
        object_class: "Issue",
        object_id: @issue.id,
        content: "Old content"
      )
      
      updated_cache = AiHelperSummaryCache.update_issue_cache(
        issue_id: @issue.id,
        content: @test_content
      )
      
      assert_equal existing_cache.id, updated_cache.id
      assert_equal @test_content, updated_cache.content
    end
  end

  context "Wiki cache methods" do
    should "find existing wiki cache" do
      cache = AiHelperSummaryCache.create!(
        object_class: "WikiPage",
        object_id: @wiki_page.id,
        content: @test_content
      )
      
      found_cache = AiHelperSummaryCache.wiki_cache(wiki_page_id: @wiki_page.id)
      assert_equal cache.id, found_cache.id
      assert_equal @test_content, found_cache.content
    end

    should "return nil when no wiki cache exists" do
      found_cache = AiHelperSummaryCache.wiki_cache(wiki_page_id: 999999)
      assert_nil found_cache
    end

    should "create new wiki cache when none exists" do
      cache = AiHelperSummaryCache.update_wiki_cache(
        wiki_page_id: @wiki_page.id,
        content: @test_content
      )
      
      assert_not_nil cache
      assert_equal "WikiPage", cache.object_class
      assert_equal @wiki_page.id, cache.object_id
      assert_equal @test_content, cache.content
    end

    should "update existing wiki cache" do
      existing_cache = AiHelperSummaryCache.create!(
        object_class: "WikiPage",
        object_id: @wiki_page.id,
        content: "Old wiki content"
      )
      
      updated_cache = AiHelperSummaryCache.update_wiki_cache(
        wiki_page_id: @wiki_page.id,
        content: @test_content
      )
      
      assert_equal existing_cache.id, updated_cache.id
      assert_equal @test_content, updated_cache.content
    end

    should "maintain separate caches for different object types" do
      issue_cache = AiHelperSummaryCache.update_issue_cache(
        issue_id: @issue.id,
        content: "Issue summary"
      )
      
      wiki_cache = AiHelperSummaryCache.update_wiki_cache(
        wiki_page_id: @wiki_page.id,
        content: "Wiki summary"
      )
      
      assert_not_equal issue_cache.id, wiki_cache.id
      assert_equal "Issue", issue_cache.object_class
      assert_equal "WikiPage", wiki_cache.object_class
    end
  end

  context "Validations" do
    should "require object_class" do
      cache = AiHelperSummaryCache.new(object_id: 1, content: "test")
      assert_not cache.valid?
      assert_includes cache.errors[:object_class], "cannot be blank"
    end

    should "require object_id" do
      cache = AiHelperSummaryCache.new(object_class: "Issue", content: "test")
      assert_not cache.valid?
      assert_includes cache.errors[:object_id], "cannot be blank"
    end

    should "require content" do
      cache = AiHelperSummaryCache.new(object_class: "Issue", object_id: 1)
      assert_not cache.valid?
      assert_includes cache.errors[:content], "cannot be blank"
    end

    should "enforce uniqueness of object_id within object_class" do
      AiHelperSummaryCache.create!(
        object_class: "Issue",
        object_id: @issue.id,
        content: "First summary"
      )
      
      duplicate_cache = AiHelperSummaryCache.new(
        object_class: "Issue",
        object_id: @issue.id,
        content: "Second summary"
      )
      
      assert_not duplicate_cache.valid?
      assert_includes duplicate_cache.errors[:object_id], "has already been taken"
    end

    should "allow same object_id for different object_class" do
      AiHelperSummaryCache.create!(
        object_class: "Issue",
        object_id: 1,
        content: "Issue summary"
      )
      
      wiki_cache = AiHelperSummaryCache.new(
        object_class: "WikiPage",
        object_id: 1,
        content: "Wiki summary"
      )
      
      assert wiki_cache.valid?
    end
  end
end
