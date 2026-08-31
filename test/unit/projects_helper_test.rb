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
end
