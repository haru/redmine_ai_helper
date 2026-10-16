# frozen_string_literal: true

# WHY THIS FILE EXISTS
#
# It stops a reconnect storm against /ai_helper/mcp (Issue #410: ~59,000
# requests/day against 16 real tools/call). The endpoint is stateless and can
# never keep a `subscriptions/listen` (SEP-2575) SSE stream open, but the gem
# serves that method with a streaming body by default. Clients saw a stream that
# "succeeded" and closed at once, and reconnected immediately, forever. This
# transport answers every `subscriptions/listen` with an immediate HTTP 404 /
# JSON-RPC -32601 error instead, so clients back off through their normal error
# path. See docs/adr/031 and docs/adr/032.
#
# Why not the gem's own `serve_subscriptions_listen: false` option: with it, a
# `subscriptions/listen` request WITHOUT an `id` is handled as a JSON-RPC
# notification and answered with HTTP 202 — a non-error that lets the reconnect
# loop continue. Verified still true on mcp 1.8.0.
#
# WHEN THIS FILE CAN BE DELETED
#
# Any one of the following:
# - The gem, constructed with `serve_subscriptions_listen: false`, answers an
#   id-less `subscriptions/listen` with an error status instead of 202. To check:
#   in AiHelperMcpController, replace `RedmineAiHelper::Mcp::Transport.new(...)`
#   with `MCP::Server::Transports::StreamableHTTPTransport.new(...,
#   serve_subscriptions_listen: false)` and run
#   test/functional/ai_helper_mcp_controller_test.rb. If the "subscriptions/listen"
#   contexts (C-1, C-2, C-6) pass, switch to that, delete this file, and point the
#   "streaming body guard" test's stub at the gem class.
# - The specified behavior for id-less requests (C-2 in
#   specs/051-mcp-reject-subscriptions-listen/contracts/mcp-endpoint.md) is
#   changed to accept 202. This needs a new ADR superseding ADR-031/032.
# - The endpoint gains real, stateful support for `subscriptions/listen`.
#
# Maintenance note: this file overrides a PRIVATE gem method, so a gem upgrade
# can break it silently. The mcp 1.8.0 upgrade did exactly that (new `auth_info:`
# keyword → HTTP 500). Always run the MCP functional tests after bumping `mcp`.

require "mcp"

module RedmineAiHelper
  module Mcp
    # Subclass of the `mcp` gem's Streamable HTTP transport (gem version 1.8.0,
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
    # A single override answers this: `handle_subscriptions_listen` (transport-level
    # rejection of the method). Since gem 1.4.0, +serves_subscriptions_listen?+ (base
    # class, defaults to `true` via the `serve_subscriptions_listen:` constructor
    # keyword) doubles as the gate that decides whether `handle_modern` calls
    # `handle_subscriptions_listen` at all; this class does not override it, so the
    # gate stays open and the rejection below is always reached.
    class Transport < MCP::Server::Transports::StreamableHTTPTransport
      private

      # Rejects `subscriptions/listen` (SEP-2575) as an unknown method instead of opening
      # the gem's default SSE notification stream.
      #
      # Overrides the private +StreamableHTTPTransport#handle_subscriptions_listen+
      # (mcp 1.8.0, `streamable_http_transport.rb:1012`), which +handle_modern+ calls
      # as `handle_subscriptions_listen(body, auth_info: ...)` for this method whenever
      # +serves_subscriptions_listen?+ is truthy — the base
      # class default, left un-overridden by this class (see
      # `specs/052-fix-mcp14-subscriptions-listen/contracts/transport-internal.md`).
      #
      # Only `body[:id]` is read; `body[:params]` (including any `notifications` filter)
      # is never inspected, no entry is added to `@listen_subscriptions`, and no thread is
      # started — the request is answered and forgotten.
      #
      # @param body [Hash] the parsed JSON-RPC request, with symbol keys
      # @param auth_info [Object, nil] OAuth auth info passed by the gem since mcp 1.8.0;
      #   unused, because the method is rejected regardless of the caller
      # @return [Array(Integer, Hash, Array<String>)] a one-shot Rack triple: HTTP 404,
      #   a plain `application/json` header, and a single JSON-RPC "Method not found"
      #   (`-32601`) error body echoing the request `id` (`null` when absent)
      def handle_subscriptions_listen(body, auth_info: nil) # rubocop:disable Lint/UnusedMethodArgument
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
