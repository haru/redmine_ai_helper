# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperProjectIndexLegendTest < ActionController::TestCase
  tests ProjectsController

  fixtures :projects, :users, :members, :member_roles, :roles, :enabled_modules

  setup do
    @request.session[:user_id] = 1
  end

  test "board display shows the AI Helper legend item for a logged in user" do
    get :index, params: { display_type: "board" }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("#ai-helper-index-legend-item"), "expected the AI Helper legend item to be present"
  end

  test "list display shows the AI Helper legend item for a logged in user" do
    get :index, params: { display_type: "list" }
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert doc.at_css("#ai-helper-index-legend-item"), "expected the AI Helper legend item to be present"
  end

  test "no legend item is rendered for a logged out user" do
    @request.session[:user_id] = nil

    get :index
    assert_response :success

    doc = Nokogiri::HTML(@response.body)
    assert_nil doc.at_css("#ai-helper-index-legend-item")
  end
end
