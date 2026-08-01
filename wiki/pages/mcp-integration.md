---
title: MCP Integration
type: component
sources: [S002, S006, S007]
updated: 2026-08-01
---

# MCP Integration

The plugin has **two independent MCP capabilities** (S002):

1. **Consume external MCP servers** — connect to Slack, GitHub, etc. and use
   their tools inside the AI chat.
2. **Expose Redmine as an MCP server** — external clients (Claude Desktop, other
   agents) query Redmine's own tools.

## Consuming external MCP servers

Configured in `config/ai_helper/config.json` (under the Redmine root) via an
`mcpServers` map; restart Redmine to apply (S002). Three transport types, with
`type` **auto-detected** from the other keys when omitted (S002):

| Type | Auto-detected when | Transport |
|---|---|---|
| `stdio` | `command` or `args` present | local process over stdin/stdout |
| `http` | `url` present, no `type` | MCP Streamable HTTP |
| `sse` | `type: "sse"` explicit | Server-Sent Events |

External connections are handled by the `ruby_llm-mcp` library, with one client
per transport (`create_stdio_client` / `create_http_client` / `create_sse_client`)
(S006).

### Dynamic agent generation

`McpServerLoader` (`lib/redmine_ai_helper/util/mcp_server_loader.rb`) does the
`type` inference above and, for each configured server, **generates a
`BaseAgent` subclass at runtime** — no per-server code, only config changes
trigger regeneration (S006). The naming follows the config key (a `slack` entry
produces a Slack MCP agent; the project also refers to these as `SubMcpAgent`
classes). Its tools are built by fetching the server's tool list and creating
tool classes dynamically (`McpTools.generate_tool_classes`), and the generated
agent joins the same dispatcher as built-in agents so orchestration is
transparent (S006). See [Multi-Agent Architecture](./multi-agent-architecture.md).

> **Read-only gotcha**: dynamically generated MCP agents are **auto-disabled
> when `read_only_mode?` is on**, because external tools carry no granular
> read/write classification, so the plugin cannot prove they are safe (S006).

## Exposing Redmine as an MCP server

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
  **HTTP 401**; MCP server disabled → **HTTP 403** (S002, S006, S007).
- **Permissions**: **all** tools are exposed by default; access is governed
  entirely by Redmine's existing permission system, checked at **each tool
  execution** against `User.current` (`view_ai_helper`, project membership, etc.)
  (S007). Every call passes `tool_call_permitted?`, which checks **both** Redmine
  permissions **and** plugin settings (e.g. whether the Vector DB is available)
  (S006).
- **No rate limiting** in the initial implementation — deliberately deferred as a
  future extension (S007).

Internal `RubyLLM::Tool` subclasses are converted into `MCP::Tool` instances by
`ToolAdapter` (`lib/redmine_ai_helper/mcp/tool_adapter.rb`), with permission
checks enforced in **both** the adapter and the server layer so unprivileged
clients never see a tool (S006).

Tool groups exposed: Issue, Project, Wiki, Repository, Board, User, Version,
File (`analyze_content_files`), and Vector (`find_similar_issues`,
`ask_with_filter` — requires [Vector Search](./vector-search.md) setup) (S002).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) — where generated MCP
  agents plug in, and the read-only mode they respect.
- [Plugin Overview](./plugin-overview.md)
