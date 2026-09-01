# ADR-031: MCP Endpoint Rejects subscriptions/listen

**Date**: 2026-08-26
**Status**: Accepted

## Context

Issue #410 reported a request storm against `/ai_helper/mcp`: roughly 59,000 requests/day against
only 16 real `tools/call` invocations. Investigation traced this to the endpoint's handling of
`subscriptions/listen` (SEP-2575 change-notification streaming):

- `RedmineAiHelper::Mcp::Server.build` passed no explicit `capabilities:` to `MCP::Server.new`, so
  the `mcp` gem's default capabilities advertised `listChanged: true` for `tools`, `prompts` and
  `resources` — a promise the plugin never fulfilled, since it never emits any
  `notifications/*/list_changed` event.
- A well-behaved MCP client that reads this capability opens a `subscriptions/listen` stream. The
  gem's `StreamableHTTPTransport` serves this at the transport layer with a Rack streaming `Proc`
  body (`streamable_http_transport.rb:886`), *before* dispatching to `Server#handle` and without
  consulting `serves_subscriptions_listen?`.
- `AiHelperMcpController#handle_request` rendered the response body with `Array(body_parts).join`.
  For a `Proc`, `Array(proc)` wraps it in a one-element array and `join` calls `#to_s` on it,
  producing the literal string `"#<Proc:0x0000ffff…>"` — returned as **HTTP 200 /
  `text/event-stream`**.
- The client sees a stream that opened and closed immediately with a 200, treats it as a
  successfully-but-briefly-open connection, does not back off per any error-handling path, and
  reconnects instantly — the observed storm.
- The `#<Proc:0x…>` string is also an internal-object-address disclosure to an unauthenticated
  read of server memory layout (mitigated by the same fix, though not the primary driver).

The endpoint is deliberately stateless: `RedmineAiHelper::Mcp::Server.build` and the transport are
constructed fresh per request, with no shared subscription registry, no `ActionController::Live`,
and no long-lived connection. There is therefore no mechanism by which a correctly implemented
`subscriptions/listen` stream could ever deliver a notification — the plugin has nothing to push
and nowhere durable to register the request that would receive it. Implementing real streaming
would mean holding a thread and a DB connection open per connected client, indefinitely, to
deliver events that never occur, and would not work across Redmine's multi-process deployments
without an external event bus.

## Decision

Reject `subscriptions/listen` and stop advertising the capability, using three coordinated
changes verified against the installed `mcp` 1.3.0 gem by prototype:

1. **Declare honestly.** `RedmineAiHelper::Mcp::Server.build` now passes explicit
   `capabilities: { tools: {}, prompts: {}, resources: {}, logging: {} }` to `MCP::Server.new`,
   removing the false `listChanged`/`subscribe` promises from both the modern `server/discover`
   result and the legacy `initialize` result. `logging` is kept because `logging/setLevel` is
   genuinely served by the gem.
2. **Refuse cleanly.** A new `RedmineAiHelper::Mcp::Transport < MCP::Server::Transports::StreamableHTTPTransport`
   overrides the public `serves_subscriptions_listen?` to return `false` (defence in depth for
   `discover_capabilities`' own stripping logic) and overrides the private
   `handle_subscriptions_listen(body)` to return a one-shot Rack triple: HTTP `404`, a plain
   `application/json` content type, and a JSON-RPC `-32601` ("Method not found") body echoing the
   request `id`. Both overrides are required — the transport intercepts the method before
   consulting capabilities at all, so the capability change alone would not stop a client that
   ignores the declaration.
3. **Never lie by accident.** The controller no longer stringifies whatever the transport hands
   back. `Array(body_parts).join` is replaced with an explicit check: a body responding to `call`
   (a streaming `Proc`) is logged via `ai_helper_logger.error`, naming the offending JSON-RPC
   method, and answered with HTTP `500` and a JSON-RPC `-32603` ("Internal error") body. This is
   orthogonal insurance against any future gem version that streams a different method — the
   condition is a value-shape check, not a method-name allowlist.

The `404`/`-32601` pairing mirrors the gem's own mapping for an unknown modern method
(`modern_http_status`), so unmodified clients need no special-casing to recognise the rejection
and back off normally.

## Consequences

- **Positive**: idle client traffic against the endpoint drops to connection setup only; daily
  request volume returns to the same order of magnitude as actual `tools/call` usage.
- **Positive**: a `subscriptions/listen` attempt now fails loudly and observably (a standard
  JSON-RPC error) instead of silently succeeding with garbage content, removing both the traffic
  storm and the incidental internal-object-address leak.
- **Positive**: any future non-enumerable transport body (not just `subscriptions/listen`) is now
  caught by the same guard and produces a logged 500 instead of a silent broken 200.
- **Negative**: this is coupled to two `mcp` gem internals — `serves_subscriptions_listen?` and the
  private `handle_subscriptions_listen` — named explicitly, with the targeted gem version recorded
  in a comment in `transport.rb`. A future gem upgrade that renames or restructures either member
  will regress silently unless the functional test suite (which asserts the observable
  404/-32601/no-`listChanged` contract, not the override mechanism) is run.
- **Negative**: real change-notification support remains unimplemented. If a future requirement
  needs it, it requires a genuinely different architecture (a shared, cross-process subscription
  registry and a way to fan out events), not an incremental extension of this fix.

## Alternatives Considered

- **Implement real notification streaming** (`ActionController::Live`, a subscription registry,
  and actual `notifications/*/list_changed` emission): rejected. The endpoint's statelessness is
  load-bearing elsewhere in this plugin's design (see the per-request `Server.build`), and the
  plugin has no events to push in the first place — building the infrastructure would add a
  standing resource cost (one thread + one DB connection per idle client, forever) to deliver
  nothing, and would not work across Redmine's multi-process deployments without a new external
  event bus.
- **Rely solely on the capability declaration and skip the transport-level rejection**: rejected —
  `handle_subscriptions_listen` is invoked unconditionally for the method before the gem consults
  `serves_subscriptions_listen?`, so a client that ignores (or never fetches) the capability
  declaration would still open the broken stream.
- **Rely solely on the transport-level rejection and skip the explicit capability declaration**:
  rejected — it would satisfy the modern `server/discover` path (via
  `serves_subscriptions_listen?`) but not the legacy `initialize` path, which serialises
  `capabilities` directly and does not consult transport state at all.
- **Monkey-patch the gem's transport class in place**: rejected in favor of a local subclass, which
  is easier to grep for, does not risk affecting other MCP client code sharing the same process
  (e.g. `ruby_llm-mcp`), and keeps the override list explicit and reviewable.
- **Silently render an empty or truncated body for a non-enumerable transport response**: rejected
  — this plugin's Constitution forbids silent fallbacks, and a quiet failure of exactly this shape
  (a garbage 200 with no log trace) is what let the original bug run for a full day before
  detection.
