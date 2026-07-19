# frozen_string_literal: true

require_relative "../test_helper"

class AiHelperChannelBindingsControllerTest < ActionController::TestCase
  fixtures :projects, :users

  setup do
    AiHelperChannelBinding.delete_all
    @request.session[:user_id] = 1
  end

  context "create" do
    should "create a binding and redirect to the channels tab" do
      post :create, params: {
        ai_helper_channel_binding: {
          channel_type: "slack", channel_id: "C123", channel_name: "#dev", project_id: 1
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      binding = AiHelperChannelBinding.for_channel("slack", "C123").first
      assert_not_nil binding
      assert_equal "#dev", binding.channel_name
      assert_equal 1, binding.project_id
    end

    should "reject a duplicate channel with an error message" do
      AiHelperChannelBinding.create!(channel_type: "slack", channel_id: "C123", project_id: 1)

      post :create, params: {
        ai_helper_channel_binding: {
          channel_type: "slack", channel_id: "C123", project_id: 2
        }
      }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      assert_predicate flash[:error], :present?
      assert_equal 1, AiHelperChannelBinding.count
    end

    should "be forbidden for non-admin users" do
      @request.session[:user_id] = 2

      post :create, params: {
        ai_helper_channel_binding: {
          channel_type: "slack", channel_id: "C999", project_id: 1
        }
      }

      assert_response :forbidden
      assert_equal 0, AiHelperChannelBinding.count
    end
  end

  context "destroy" do
    setup do
      @binding = AiHelperChannelBinding.create!(channel_type: "slack", channel_id: "C123", project_id: 1)
    end

    should "delete the binding and redirect to the channels tab" do
      delete :destroy, params: { id: @binding.id }

      assert_redirected_to controller: "ai_helper_settings", action: :index, tab: "channels"
      assert_nil AiHelperChannelBinding.find_by(id: @binding.id)
    end

    should "be forbidden for non-admin users" do
      @request.session[:user_id] = 2

      delete :destroy, params: { id: @binding.id }

      assert_response :forbidden
      assert_not_nil AiHelperChannelBinding.find_by(id: @binding.id)
    end
  end
end
