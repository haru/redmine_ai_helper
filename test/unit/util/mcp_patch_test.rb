require_relative "../../test_helper"

class McpPatchTest < ActiveSupport::TestCase
  context "McpPatch" do
    should "patch notifications/initialized to not include id" do
      coordinator = mock("coordinator")

      # Verify that the notification is sent with add_id: false
      coordinator.expects(:request).with(
        { jsonrpc: "2.0", method: "notifications/initialized" },
        add_id: false,
        wait_for_response: false,
      )

      notification = RubyLLM::MCP::Notifications::Initialize.new(coordinator)
      notification.call
    end

    should "notification body not contain id key" do
      notification = RubyLLM::MCP::Notifications::Initialize.new(nil)
      body = notification.notification_body

      assert_equal "2.0", body[:jsonrpc]
      assert_equal "notifications/initialized", body[:method]
      assert_not body.key?(:id), "Notification body must not contain an :id key"
      assert_not body.key?("id"), "Notification body must not contain an 'id' key"
    end
  end
end
