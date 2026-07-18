# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperSettingsHelperTest < ActionView::TestCase
  include AiHelperSettingsHelper

  context "ai_helper_settings_tabs" do
    should "return 3 tab definitions in order: general, model, vector" do
      f = build_form_builder
      tabs = ai_helper_settings_tabs(f)

      assert_equal 3, tabs.length

      assert_equal "general", tabs[0][:name]
      assert_equal "ai_helper_settings/general_tab", tabs[0][:partial]
      assert_equal :"ai_helper.settings.tab_general", tabs[0][:label]
      assert_equal f, tabs[0][:f]

      assert_equal "model", tabs[1][:name]
      assert_equal "ai_helper_settings/model_tab", tabs[1][:partial]
      assert_equal :"ai_helper.settings.tab_model", tabs[1][:label]
      assert_equal f, tabs[1][:f]

      assert_equal "vector", tabs[2][:name]
      assert_equal "ai_helper_settings/vector_tab", tabs[2][:partial]
      assert_equal :"ai_helper.settings.tab_vector", tabs[2][:label]
      assert_equal f, tabs[2][:f]
    end
  end

  context "ai_helper_settings_tab_for_error" do
    should "return general for attachment_max_size_mb" do
      assert_equal "general", ai_helper_settings_tab_for_error("attachment_max_size_mb")
    end

    should "return model for think_model_profile_id" do
      assert_equal "model", ai_helper_settings_tab_for_error("think_model_profile_id")
    end

    should "return vector for vector_search_uri" do
      assert_equal "vector", ai_helper_settings_tab_for_error("vector_search_uri")
    end

    should "return vector for vector_model_profile_id" do
      assert_equal "vector", ai_helper_settings_tab_for_error("vector_model_profile_id")
    end

    should "return nil for unknown attribute" do
      assert_nil ai_helper_settings_tab_for_error("unknown_attribute")
    end
  end

  context "ai_helper_settings_selected_tab" do
    should "return error-based tab when errors present" do
      tab = ai_helper_settings_selected_tab(
        ["attachment_max_size_mb"],
        "vector"
      )
      assert_equal "general", tab
    end

    should "fall back to params_tab when no error mapping exists" do
      tab = ai_helper_settings_selected_tab(
        ["unknown_attribute"],
        "model"
      )
      assert_equal "model", tab
    end

    should "return params_tab when errors array is empty" do
      tab = ai_helper_settings_selected_tab([], "vector")
      assert_equal "vector", tab
    end

    should "return nil when errors array is empty and params_tab is nil" do
      tab = ai_helper_settings_selected_tab([], nil)
      assert_nil tab
    end
  end

  private

  def build_form_builder
    setting = AiHelperSetting.new
    template = ActionView::Base.empty
    template.class.include ActionView::Helpers::FormHelper
    ActionView::Helpers::FormBuilder.new(
      :ai_helper_setting,
      setting,
      template,
      {}
    )
  end
end
