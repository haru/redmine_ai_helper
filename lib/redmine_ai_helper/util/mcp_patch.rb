# frozen_string_literal: true

module RedmineAiHelper
  module Util
    # Monkey-patch for ruby_llm-mcp 0.8.0
    #
    # Fixes a bug where RubyLLM::MCP::Notifications::Initialize sends the
    # "notifications/initialized" JSON-RPC notification with an `id` field.
    # Per JSON-RPC 2.0 spec, notifications MUST NOT include an `id`.
    # Servers such as GitHub Copilot MCP correctly reject this with:
    #   "unexpected id for notifications/initialized"
    #
    # This patch overrides `call` to use `add_id: false`.
    # It can be removed once ruby_llm-mcp releases a fix upstream.
    module McpPatch
      # Applies the monkey-patch by prepending NotificationFix into the MCP notification class.
      # @return [void]
      def self.apply!
        RubyLLM::MCP::Notifications::Initialize.prepend(NotificationFix)
      end

      # Prepended module to fix the notification id issue
      module NotificationFix
        # Sends the initialization notification without an id field.
        # @return [void]
        def call
          @coordinator.request(notification_body, add_id: false, wait_for_response: false)
        end
      end
    end
  end
end
