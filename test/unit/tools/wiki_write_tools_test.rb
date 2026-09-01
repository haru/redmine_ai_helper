require File.expand_path("../../../test_helper", __FILE__)

class WikiWriteToolsTest < ActiveSupport::TestCase
  fixtures :projects, :wikis, :wiki_pages, :wiki_contents, :users,
           :roles, :members, :member_roles, :enabled_modules

  def setup
    @provider = RedmineAiHelper::Tools::WikiWriteTools.new
    @project = Project.find(1)
    EnabledModule.create!(project_id: 1, name: "ai_helper")
    User.current = User.find(1) # admin
  end

  context "wiki_add_page" do
    should "create a new wiki page with correct title, content, and author" do
      page_count = WikiPage.count
      result = @provider.wiki_add_page(project_id: 1, title: "NewTestPage", content: "Test content")

      assert_equal page_count + 1, WikiPage.count
      assert_equal "NewTestPage", result[:title]
      assert_equal "Test content", result[:text]
      assert_equal User.current.id, result[:author][:id]
      assert_equal 1, result[:version]
    end

    should "create a wiki page as child when parent_title is given" do
      result = @provider.wiki_add_page(
        project_id: 1,
        title: "ChildTestPage",
        content: "Child content",
        parent_title: "CookBook_documentation"
      )
      page = WikiPage.find(result[:id])

      assert_not_nil page.parent
      assert_equal "CookBook_documentation", page.parent.title
      assert_equal({ id: page.parent.id, title: "CookBook_documentation" }, result[:parent])
    end

    should "raise error when permission denied (no :edit_wiki_pages)" do
      role = Role.find(1) # Manager
      role.permissions = (role.permissions + [ :view_ai_helper ]).reject { |p| p == :edit_wiki_pages }
      role.save!
      User.current = User.find(2) # Jsmith has Manager role in project 1

      assert_raises(RuntimeError, "Permission denied") do
        @provider.wiki_add_page(project_id: 1, title: "FailPagePermission", content: "content")
      end
      assert_nil WikiPage.find_by(title: "FailPagePermission")
    end

    should "raise error when ai_helper module is disabled" do
      EnabledModule.where(project_id: 1, name: "ai_helper").delete_all

      assert_raises(RuntimeError) do
        @provider.wiki_add_page(project_id: 1, title: "FailPageModule", content: "content")
      end
    end

    should "raise error when wiki is not found" do
      # Project 3 has no wiki record in the database
      EnabledModule.create!(project_id: 3, name: "ai_helper")

      assert_raises(RuntimeError) do
        @provider.wiki_add_page(project_id: 3, title: "FailPageNoWiki", content: "content")
      end
    end

    should "raise error when title already exists" do
      assert_raises(RuntimeError) do
        @provider.wiki_add_page(project_id: 1, title: "CookBook_documentation", content: "duplicate")
      end
    end

    should "raise error when parent_title is not found" do
      assert_raises(RuntimeError) do
        @provider.wiki_add_page(
          project_id: 1,
          title: "OrphanPage",
          content: "content",
          parent_title: "NonExistentParent"
        )
      end
    end

    should "raise error when project_id is nil" do
      assert_raises(RuntimeError, "project_id is required") do
        @provider.wiki_add_page(project_id: nil, title: "FailPage", content: "content")
      end
    end

    should "raise error when title is nil" do
      assert_raises(RuntimeError, "title is required") do
        @provider.wiki_add_page(project_id: 1, title: nil, content: "content")
      end
    end

    should "raise error when content is nil" do
      assert_raises(RuntimeError, "content is required") do
        @provider.wiki_add_page(project_id: 1, title: "NilContentPage", content: nil)
      end
    end
  end

  context "wiki_update_page" do
    should "update content only and increment version with author set" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Another_page")
      old_version = page.content.version

      result = @provider.wiki_update_page(project_id: 1, title: "Another_page", content: "Updated content")

      assert_equal "Updated content", result[:text]
      page.content.reload

      assert_equal old_version + 1, page.content.version
      assert_equal User.current.id, result[:author][:id]
    end

    should "rename page only when new_title is given without content" do
      result = @provider.wiki_update_page(project_id: 1, title: "Another_page", new_title: "RenamedPage")
      page = WikiPage.find(result[:id])

      assert_equal "RenamedPage", page.title
    end

    should "update both content and new_title in one call" do
      result = @provider.wiki_update_page(
        project_id: 1,
        title: "Another_page",
        content: "New content",
        new_title: "RenamedPage2"
      )
      page = WikiPage.find(result[:id])

      assert_equal "RenamedPage2", page.title
      assert_equal "New content", result[:text]
    end

    should "store edit comment in wiki_content.comments" do
      wiki = Wiki.find_by(project_id: 1)
      @provider.wiki_update_page(
        project_id: 1,
        title: "Another_page",
        content: "With comment",
        comment: "My edit comment"
      )
      page = wiki.find_page("Another_page")

      assert_equal "My edit comment", page.content.comments
    end

    should "raise error when permission denied (no :edit_wiki_pages)" do
      role = Role.find(1) # Manager
      role.permissions = (role.permissions + [ :view_ai_helper ]).reject { |p| p == :edit_wiki_pages }
      role.save!
      User.current = User.find(2) # Jsmith has Manager role in project 1

      assert_raises(RuntimeError, "Permission denied") do
        @provider.wiki_update_page(project_id: 1, title: "Another_page", content: "fail")
      end
    end

    should "raise error when page is not found" do
      assert_raises(RuntimeError) do
        @provider.wiki_update_page(project_id: 1, title: "NonExistentPage", content: "content")
      end
    end

    should "raise error when ai_helper module is disabled" do
      EnabledModule.where(project_id: 1, name: "ai_helper").delete_all

      assert_raises(RuntimeError) do
        @provider.wiki_update_page(project_id: 1, title: "Another_page", content: "content")
      end
    end

    should "raise error when project_id is nil" do
      assert_raises(RuntimeError, "project_id is required") do
        @provider.wiki_update_page(project_id: nil, title: "Another_page", content: "content")
      end
    end

    should "raise error when title is nil" do
      assert_raises(RuntimeError, "title is required") do
        @provider.wiki_update_page(project_id: 1, title: nil, content: "content")
      end
    end

    should "set parent to an existing page when parent_title is given" do
      result = @provider.wiki_update_page(project_id: 1, title: "Another_page", parent_title: "CookBook_documentation")
      page = WikiPage.find(result[:id])

      assert_equal "CookBook_documentation", page.parent.title
      assert_equal({ id: page.parent.id, title: "CookBook_documentation" }, result[:parent])
    end

    should "clear the parent (make top-level) when parent_title is an empty string" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Child_1")
      assert_not_nil page.parent

      result = @provider.wiki_update_page(project_id: 1, title: "Child_1", parent_title: "")
      page.reload

      assert_nil page.parent
      assert_nil result[:parent]
    end

    should "leave the parent unchanged when parent_title is omitted" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Child_1")
      original_parent_id = page.parent_id

      result = @provider.wiki_update_page(project_id: 1, title: "Child_1", content: "updated content")
      page.reload

      assert_equal original_parent_id, page.parent_id
      assert_equal({ id: original_parent_id, title: "Another_page" }, result[:parent])
    end

    should "raise error and leave parent unchanged when parent_title is not found" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Another_page")
      original_parent_id = page.parent_id

      error = assert_raises(RuntimeError) do
        @provider.wiki_update_page(project_id: 1, title: "Another_page", parent_title: "NonExistentParent")
      end
      assert_equal "Parent page not found: title = NonExistentParent", error.message
      page.reload
      assert_nil original_parent_id
      assert_nil page.parent_id
    end

    should "raise error and leave parent unchanged when parent_title is a self-reference" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Child_1")
      original_parent_id = page.parent_id

      error = assert_raises(RuntimeError) do
        @provider.wiki_update_page(project_id: 1, title: "Child_1", parent_title: "Child_1")
      end
      assert_equal "Cannot set parent page: circular reference detected (title = Child_1)", error.message
      page.reload
      assert_equal original_parent_id, page.parent_id
    end

    should "raise error and leave parent unchanged when parent_title is a descendant page" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Child_1")
      original_parent_id = page.parent_id

      error = assert_raises(RuntimeError) do
        @provider.wiki_update_page(project_id: 1, title: "Child_1", parent_title: "Child_1_1")
      end
      assert_equal "Cannot set parent page: circular reference detected (title = Child_1_1)", error.message
      page.reload
      assert_equal original_parent_id, page.parent_id
    end

    should "raise error when permission denied (no :edit_wiki_pages) and leave parent unchanged" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Another_page")
      original_parent_id = page.parent_id

      role = Role.find(1) # Manager
      role.permissions = (role.permissions + [ :view_ai_helper ]).reject { |p| p == :edit_wiki_pages }
      role.save!
      User.current = User.find(2) # Jsmith has Manager role in project 1

      assert_raises(RuntimeError, "Permission denied") do
        @provider.wiki_update_page(project_id: 1, title: "Another_page", parent_title: "CookBook_documentation")
      end
      page.reload
      assert_nil original_parent_id
      assert_nil page.parent_id
    end

    should "apply both parent_title and new_title in one call" do
      result = @provider.wiki_update_page(
        project_id: 1,
        title: "Another_page",
        new_title: "RenamedPage3",
        parent_title: "CookBook_documentation"
      )
      page = WikiPage.find(result[:id])

      assert_equal "RenamedPage3", page.title
      assert_equal "CookBook_documentation", page.parent.title
      assert_equal "RenamedPage3", result[:title]
      assert_equal({ id: page.parent.id, title: "CookBook_documentation" }, result[:parent])
    end

    should "roll back content changes when parent_title update fails" do
      wiki = Wiki.find_by(project_id: 1)
      page = wiki.find_page("Another_page")
      original_text = page.content.text

      assert_raises(RuntimeError) do
        @provider.wiki_update_page(
          project_id: 1,
          title: "Another_page",
          content: "should not persist",
          parent_title: "NonExistentParent"
        )
      end

      page.reload
      assert_equal original_text, page.content.text
    end
  end

  context "wiki_delete_page" do
    should "delete page and return deleted: true with title" do
      page = WikiPage.find_by(title: "Another_page")
      page_id = page.id

      result = @provider.wiki_delete_page(project_id: 1, title: "Another_page")

      assert_equal true, result[:deleted]
      assert_equal "Another_page", result[:title]
      assert_nil WikiPage.find_by(id: page_id)
      assert_nil WikiContent.find_by(page_id: page_id)
    end

    should "raise error when permission denied (no :delete_wiki_pages) and leave page intact" do
      role = Role.find(1) # Manager
      role.permissions = (role.permissions + [ :view_ai_helper ]).reject { |p| p == :delete_wiki_pages }
      role.save!
      User.current = User.find(2) # Jsmith has Manager role in project 1

      assert_raises(RuntimeError, "Permission denied") do
        @provider.wiki_delete_page(project_id: 1, title: "Another_page")
      end
      assert_not_nil WikiPage.find_by(title: "Another_page")
    end

    should "raise error when page is not found" do
      assert_raises(RuntimeError) do
        @provider.wiki_delete_page(project_id: 1, title: "NonExistentPage")
      end
    end

    should "raise error when ai_helper module is disabled" do
      EnabledModule.where(project_id: 1, name: "ai_helper").delete_all

      assert_raises(RuntimeError) do
        @provider.wiki_delete_page(project_id: 1, title: "Another_page")
      end
    end

    should "raise error when project_id is nil" do
      assert_raises(RuntimeError, "project_id is required") do
        @provider.wiki_delete_page(project_id: nil, title: "Another_page")
      end
    end

    should "raise error when title is nil" do
      assert_raises(RuntimeError, "title is required") do
        @provider.wiki_delete_page(project_id: 1, title: nil)
      end
    end
  end

  context "write_tool?" do
    should "mark wiki_add_page as a write tool" do
      tool_class = RedmineAiHelper::Tools::WikiWriteTools.tool_classes.find { |tc| tc.name.end_with?("::WikiAddPage") }

      assert_equal true, tool_class.write_tool?
    end

    should "mark wiki_update_page as a write tool" do
      tool_class = RedmineAiHelper::Tools::WikiWriteTools.tool_classes.find { |tc| tc.name.end_with?("::WikiUpdatePage") }

      assert_equal true, tool_class.write_tool?
    end

    should "mark wiki_delete_page as a write tool" do
      tool_class = RedmineAiHelper::Tools::WikiWriteTools.tool_classes.find { |tc| tc.name.end_with?("::WikiDeletePage") }

      assert_equal true, tool_class.write_tool?
    end
  end
end
