# frozen_string_literal: true

require File.expand_path("../../../test_helper", __FILE__)
require "redmine_ai_helper/mcp/session_strategy"

class StatelessAuthStrategyTest < ActiveSupport::TestCase
  def setup
    @active_user = User.find(1) # admin user
    @api_key = @active_user.api_key
  end

  context "StatelessAuthStrategy.authenticate" do
    should "return the user when a valid API key is provided" do
      request = mock_request_with_api_key(@api_key)
      user = RedmineAiHelper::Mcp::StatelessAuthStrategy.authenticate(request)

      assert_equal @active_user.id, user.id
    end

    should "return nil when API key is invalid" do
      request = mock_request_with_api_key("invalid_key_xyz")
      user = RedmineAiHelper::Mcp::StatelessAuthStrategy.authenticate(request)

      assert_nil user
    end

    should "return nil when API key is missing" do
      request = mock_request_with_api_key(nil)
      user = RedmineAiHelper::Mcp::StatelessAuthStrategy.authenticate(request)

      assert_nil user
    end

    should "return nil when API key is empty string" do
      request = mock_request_with_api_key("")
      user = RedmineAiHelper::Mcp::StatelessAuthStrategy.authenticate(request)

      assert_nil user
    end

    should "return nil when user account is not active" do
      locked_user = User.find(1)
      locked_key = locked_user.api_key
      locked_user.update_column(:status, User::STATUS_LOCKED)
      request = mock_request_with_api_key(locked_key)
      user = RedmineAiHelper::Mcp::StatelessAuthStrategy.authenticate(request)

      assert_nil user
    ensure
      User.find(1).update_column(:status, User::STATUS_ACTIVE)
    end
  end

  private

  def mock_request_with_api_key(key)
    request = mock
    request.stubs(:headers).returns({ "X-Redmine-API-Key" => key })
    request
  end
end
