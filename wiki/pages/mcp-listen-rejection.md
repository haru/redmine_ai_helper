---
title: MCP subscriptions/listen Rejection
type: decision
sources: [S027, S028, S029]
updated: 2026-08-28
---

# MCP `subscriptions/listen` Rejection (ADR-031)

Part of [MCP Server Endpoint](./mcp-server-endpoint.md). **Change
notifications are not supported**, by design (ADR-031, S028). The endpoint
does not implement `subscriptions/listen` (SEP-2575) or advertise
`listChanged`/`subscribe` capabilities.

> **mcp 1.4.0 update**: part 2 of the fix below (the
> `serves_subscriptions_listen?` override) was later deleted to fix a
> regression introduced by the `mcp` gem's 1.3.0→1.4.0 upgrade. See
> [MCP subscriptions/listen 1.4.0 Fix](./mcp-listen-rejection-1-4-0-fix.md)
> (ADR-032).

**Root cause it fixed**: `Server.build` used to pass no explicit
`capabilities:`, so the `mcp` gem's defaults advertised `listChanged: true`
for `tools`/`prompts`/`resources` — a promise never kept, since the plugin
never emits `notifications/*/list_changed`. A well-behaved client that read
this capability opened a `subscriptions/listen` stream; the gem serves that
at the **transport layer** as a Rack streaming `Proc` body, and the
controller's `Array(body_parts).join` silently called `Proc#to_s` on it,
returning **HTTP 200 `text/event-stream`** with a garbage body. Clients read
the 200 as success and reconnected instantly on the immediate close — the
observed storm (Issue #410: ~59k requests/day against 16 real `tools/call`
calls) (S027, S028).

**Fix, three coordinated parts (mcp 1.3.0, as originally shipped)**:
1. `Server.build` now passes explicit
   `capabilities: { tools: {}, prompts: {}, resources: {}, logging: {} }`
   (`logging` kept — `logging/setLevel` is genuinely served). Needed because
   the legacy `initialize` result serialises `capabilities` directly,
   bypassing `discover_capabilities` (S027).
2. `RedmineAiHelper::Mcp::Transport < MCP::Server::Transports::StreamableHTTPTransport`
   overrides `serves_subscriptions_listen?` → `false` **and** the private
   `handle_subscriptions_listen(body)` → a one-shot `404` / JSON-RPC `-32601`
   response. Both were required under 1.3.0: the gem's `handle_modern`
   intercepted `subscriptions/listen` *before* consulting capabilities at all,
   so capability honesty alone couldn't stop a client that ignored it (S027,
   S028). **The `serves_subscriptions_listen?` half was later deleted — see
   the 1.4.0 fix page linked above.**
3. The controller no longer stringifies whatever the transport returns — a
   body responding to `:call` (a streaming `Proc`) is logged via
   `ai_helper_logger.error` and answered with HTTP 500 / JSON-RPC `-32603`,
   replacing the silent-fallback `Array(...).join`. A value-shape check, not
   a method-name allowlist, so it also catches a future gem version streaming
   a different method (S027, S028).

> **Gem-version coupling gotcha (original)**: `serves_subscriptions_listen?`
> and `handle_subscriptions_listen` were named `mcp` 1.3.0 internals, the
> latter private. A gem upgrade that renames or restructures either regresses
> **silently** — the functional test suite, not the override mechanism, is
> the only safety net (ADR-031 Negative consequences; S027, S028). This is
> exactly what happened at 1.4.0 — see the linked fix page for the updated
> gotcha and outstanding follow-ups (S029).

## Alternatives rejected

- Real notification streaming (`ActionController::Live`, a subscription
  registry): rejected — the plugin has no events to push and this endpoint is
  deliberately per-request/stateless; would cost one thread + DB connection
  per idle client forever, and wouldn't work across multi-process Redmine
  without an external event bus (S027, S028).
- Capability declaration only, no transport-level rejection: rejected — the
  gem invokes `handle_subscriptions_listen` before checking capabilities
  (S027, S028).
- Transport-level rejection only, no capability declaration: rejected — the
  legacy `initialize` path serialises `capabilities` directly and never
  consults transport state (S027, S028).
- Monkey-patching the gem's transport class in place: rejected in favor of a
  local subclass — easier to grep, doesn't risk affecting `ruby_llm-mcp`
  client code sharing the same process (S028).

## Related

- [MCP subscriptions/listen 1.4.0 Fix](./mcp-listen-rejection-1-4-0-fix.md) —
  ADR-032: the regression this original fix suffered under `mcp` 1.4.0, and
  what changed.
- [MCP Server Endpoint](./mcp-server-endpoint.md) — the endpoint this decision
  applies to.
- [MCP Integration](./mcp-integration.md) — the plugin's overall two-capability
  MCP split.
