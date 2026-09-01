---
title: MCP Server Endpoint
type: component
sources: [S002, S006, S007, S018, S028, S030, S031]
updated: 2026-08-28
---

# MCP Server Endpoint

How the plugin exposes Redmine itself as an MCP server (the other direction is
[MCP Integration](./mcp-integration.md#consuming-external-mcp-servers)).

Served by `AiHelperMcpController`, enabled via the "MCP Server" admin setting —
the global `mcp_server_enabled` flag gates the entire endpoint (S002, S006).

- **Endpoints**: `POST /ai_helper/mcp` carries JSON-RPC; `GET`/`DELETE` exist
  only because the MCP spec requires them and are unused in stateless mode (S002).
  The transport is **Streamable HTTP only** — no other transport is offered (S007).
- **Mode**: MCP Streamable HTTP in **stateless, JSON-response** mode
  (`stateless: true`, `enable_json_response: true`) — all traffic is POST +
  JSON-RPC, no SSE streaming (S002). Sessions hold **no server-side state**; each
  request re-authenticates by its API key (S007).
- **Protocol methods** supported: `initialize`, `tools/list`, `tools/call`, and
  the `notifications/initialized` message (S007).
- **Auth gotcha**: every request needs the `X-Redmine-API-Key` header, validated
  per-request (via `SessionStrategy`) against the user account. No/invalid key →
  **HTTP 401**; MCP server disabled → **HTTP 403**, and both checks run *before*
  any method-specific handling, including the
  [`subscriptions/listen` rejection](./mcp-listen-rejection.md) (S002, S006, S007).
- **Change notifications are not supported.** See
  [MCP subscriptions/listen Rejection](./mcp-listen-rejection.md) (ADR-031) for
  why, and the gem-version-coupling gotcha it left behind — which materialized
  once already, fixed in
  [MCP subscriptions/listen 1.4.0 Fix](./mcp-listen-rejection-1-4-0-fix.md)
  (ADR-032) (S027, S028, S029, S030, S031).
- **Permissions**: **all** tools are exposed by default; access is governed
  entirely by Redmine's existing permission system, checked at **each tool
  execution** against `User.current` (`view_ai_helper`, project membership, etc.)
  (S007). Every call passes `tool_call_permitted?`, which checks **both** Redmine
  permissions **and** plugin settings (e.g. whether the Vector DB is available)
  (S006).
- **No rate limiting** in the initial implementation — deliberately deferred as a
  future extension (S007).
- **Anonymous-endpoint pattern**: this controller established how the plugin
  serves anonymous POSTs — `skip_before_action :verify_authenticity_token` plus
  `skip_before_action :check_if_login_required, raise: false`, the latter being
  the fix for 403s under `Setting.login_required` (Issue #304). The inbound chat
  webhook endpoint reuses it verbatim — see
  [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) (S018).

Internal `RubyLLM::Tool` subclasses are converted into `MCP::Tool` instances by
`ToolAdapter` (`lib/redmine_ai_helper/mcp/tool_adapter.rb`), with permission
checks enforced in **both** the adapter and the server layer so unprivileged
clients never see a tool (S006).

Tool groups exposed: Issue, Project, Wiki, Repository, Board, User, Version,
File (`analyze_content_files`), and Vector (`find_similar_issues`,
`ask_with_filter` — requires [Vector Search](./vector-search.md) setup) (S002).

## Related

- [MCP subscriptions/listen Rejection](./mcp-listen-rejection.md) — ADR-031:
  why change notifications are rejected, and the gem-coupling gotcha.
- [MCP subscriptions/listen 1.4.0 Fix](./mcp-listen-rejection-1-4-0-fix.md) —
  ADR-032: the `mcp` 1.4.0 regression that gotcha predicted, and the fix.
- [MCP Integration](./mcp-integration.md) — the consuming-external-servers half
  and the plugin's overall two-capability split.
- [Inbound Webhook Endpoint](./inbound-webhook-endpoint.md) — reuses this
  controller's anonymous-endpoint pattern.
- [Vector Search](./vector-search.md) — required for the Vector tool group.
