require_relative "../test_helper"

class ProjectsHelperTest < ActionView::TestCase
  include ProjectsHelper
  include ERB::Util

  Column = Struct.new(:name)

  setup do
    @original_current_user = User.current
    @current_user = User.find(1)
    User.current = @current_user
    @project_with_module = Project.create!(name: "AI Helper Project", identifier: "ai-helper-project")
    @project_with_module.enable_module!(:ai_helper)
    @project_without_module = Project.create!(name: "Plain Project", identifier: "plain-project")
  end

  teardown do
    User.current = @original_current_user
    @project_with_module.destroy if @project_with_module&.persisted?
    @project_without_module.destroy if @project_without_module&.persisted?
  end

  should "append the AI Helper icon to project board when the module is enabled" do
    html = render_project_hierarchy([ @project_with_module ])

    assert_includes html, "icon-ai-helper-module"
    assert_includes html, "icon--ai-helper-robot"
  end

  should "not append the AI Helper icon to project board when the module is not enabled" do
    html = render_project_hierarchy([ @project_without_module ])

    assert_no_match(/icon-ai-helper-module/, html)
    assert_no_match(/icon--ai-helper-robot/, html)
  end

  should "place the AI Helper icon right after the existing icons and before the description" do
    @project_with_module.update!(description: "This is a description")

    html = render_project_hierarchy([ @project_with_module ])
    doc = Nokogiri::HTML::DocumentFragment.parse(html)
    container = doc.at_css("a[href='#{project_path(@project_with_module)}']").parent

    ai_helper_index = container.children.index { |node| node["class"]&.include?("icon-ai-helper-module") }
    description_node_index = container.children.index do |node|
      node.name == "div" && node.matches?("div.wiki.description")
    end

    assert_not_nil ai_helper_index, "expected the AI Helper icon to be present"
    assert_not_nil description_node_index, "expected the description div to be present"
    assert_operator ai_helper_index, :<, description_node_index,
                     "expected the AI Helper icon to appear before the description"
  end

  should "not append the AI Helper icon to a project whose identifier is a prefix match of another project's identifier" do
    # sample-2 is created (and thus positioned in the tree) before sample, so a
    # partial-match link search would incorrectly pick sample-2's link first.
    sample2_project = Project.create!(name: "Sample 2", identifier: "sample-2")
    sample_project = Project.create!(name: "Sample", identifier: "sample")
    sample_project.enable_module!(:ai_helper)

    html = render_project_hierarchy([ sample2_project, sample_project ])
    doc = Nokogiri::HTML::DocumentFragment.parse(html)

    sample_container = doc.at_css("a[href='#{project_path(sample_project)}']").parent
    sample2_container = doc.at_css("a[href='#{project_path(sample2_project)}']").parent

    assert_includes sample_container.to_s, "icon-ai-helper-module"
    assert_not_includes sample2_container.to_s, "icon-ai-helper-module"
  ensure
    sample_project&.destroy if sample_project&.persisted?
    sample2_project&.destroy if sample2_project&.persisted?
  end
end
