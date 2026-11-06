# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperWikiTypoOverlayTest < ActionController::TestCase
  tests WikiController

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :enabled_modules,
           :wikis, :wiki_pages, :wiki_contents, :wiki_content_versions

  setup do
    @project = projects(:projects_001)
    User.current = User.find(1)
    @request.session[:user_id] = User.current.id
    EnabledModule.create!(project_id: @project.id, name: "ai_helper")
  end

  teardown do
    User.current = nil
  end

  test "wiki edit page typo overlay labels are built by TypoCheckLabels" do
    get :edit, params: { project_id: @project.identifier, id: "CookBook_documentation" }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    overlay = doc.at_css("#ai-helper-wiki-typo-overlay")
    assert overlay, "expected the wiki typo overlay to be rendered"
    config = JSON.parse(overlay["data-config"])
    assert_equal RedmineAiHelper::Util::TypoCheckLabels.labels.stringify_keys, config["labels"]
    assert_equal "/projects/#{@project.identifier}/ai_helper/check_typos", config["endpoint"]
  end
end
