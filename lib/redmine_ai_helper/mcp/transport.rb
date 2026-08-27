# frozen_string_literal: true

require "mcp"

module RedmineAiHelper
  module Mcp
    # Subclass of the `mcp` gem's Streamable HTTP transport (gem version 1.3.0,
    # +MCP::Server::Transports::StreamableHTTPTransport+) whose sole purpose is to
    # declare, honestly and at the transport layer, that this endpoint does not serve
    # `subscriptions/listen` (SEP-2575 change-notification streaming).
    #
    # This plugin's MCP endpoint is stateless: a fresh +MCP::Server+ and transport are
    # built per request (see {RedmineAiHelper::Mcp::Server.build}), so there is no
    # process-local registry to fan notifications out to, and the plugin never emits
    # `notifications/*/list_changed`. Left unmodified, the gem still advertises
    # `listChanged`/`subscribe` capabilities and serves `subscriptions/listen` with a
    # long-lived SSE stream, which invites well-behaved clients to open a subscription
    # that is silently closed — see +docs/adr/031-mcp-endpoint-rejects-subscriptions-listen.md+.
    #
    # Two overrides answer this:
    # - {#serves_subscriptions_listen?} (capability-declaration honesty)
    # - `handle_subscriptions_listen` (transport-level rejection of the method)
    class Transport < MCP::Server::Transports::StreamableHTTPTransport
      # Declares that this endpoint does not serve `subscriptions/listen` (SEP-2575).
      #
      # Overrides the gem's hardcoded `true` (mcp 1.3.0,
      # `streamable_http_transport.rb:265`). Consumed by
      # `MCP::Server#discover_capabilities` (`server.rb:1188`), which strips the
      # `listChanged`/`subscribe` capability flags from the `server/discover` result
      # when this is falsey. This is defence in depth alongside the explicit
      # `capabilities:` passed by {RedmineAiHelper::Mcp::Server.build}: even if a future
      # gem version reintroduces a default `listChanged` promise, `server/discover`
      # stays honest.
      #
      # @return [Boolean] always `false`
      def serves_subscriptions_listen?
        false
      end

      private

      # Rejects `subscriptions/listen` (SEP-2575) as an unknown method instead of opening
      # the gem's default SSE notification stream.
      #
      # Overrides the private +StreamableHTTPTransport#handle_subscriptions_listen+
      # (mcp 1.3.0, `streamable_http_transport.rb:824`), which +handle_modern+ calls
      # unconditionally for this method, *without* consulting
      # {#serves_subscriptions_listen?} — so this override is required in addition to
      # that one (see `specs/051-mcp-reject-subscriptions-listen/contracts/transport-internal.md`).
      #
      # Only `body[:id]` is read; `body[:params]` (including any `notifications` filter)
      # is never inspected, no entry is added to `@listen_subscriptions`, and no thread is
      # started — the request is answered and forgotten.
      #
      # @param body [Hash] the parsed JSON-RPC request, with symbol keys
      # @return [Array(Integer, Hash, Array<String>)] a one-shot Rack triple: HTTP 404,
      #   a plain `application/json` header, and a single JSON-RPC "Method not found"
      #   (`-32601`) error body echoing the request `id` (`null` when absent)
      def handle_subscriptions_listen(body)
        json = JSON.generate(
          jsonrpc: "2.0",
          id: body[:id],
          error: {
            code: JsonRpcHandler::ErrorCode::METHOD_NOT_FOUND,
            message: "Method not found",
            data: "subscriptions/listen"
          }
        )

        [ 404, { "content-type" => "application/json" }, [ json ] ]
      end
    end
  end
end
