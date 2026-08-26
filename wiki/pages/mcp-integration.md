---
title: MCP Integration
type: component
sources: [S002, S006, S016]
updated: 2026-08-26
---

# MCP Integration

The plugin has **two independent MCP capabilities** (S002):

1. **Consume external MCP servers** — connect to Slack, GitHub, etc. and use
   their tools inside the AI chat.
2. **Expose Redmine as an MCP server** — external clients (Claude Desktop, other
   agents) query Redmine's own tools. See
   [MCP Server Endpoint](./mcp-server-endpoint.md) for that side, including the
   endpoint's auth, permissions, and its `subscriptions/listen` rejection.

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
> For the same reason, these agents don't get the default `BaseAgent#can_write?`
> (it depends on the same missing classification) — they override it to `true`
> instead of guessing `false`, since read-only mode already disables the whole
> agent above. See
> [Agent Write-Capability Routing](./agent-write-capability-routing.md) (S016).

## Related

- [MCP Server Endpoint](./mcp-server-endpoint.md) — exposing Redmine as an MCP
  server: auth, permissions, tool groups, and the `subscriptions/listen`
  rejection (ADR-031).
- [Multi-Agent Architecture](./multi-agent-architecture.md) — where generated MCP
  agents plug in, and the read-only mode they respect.
- [Plugin Overview](./plugin-overview.md)
- [Agent Write-Capability Routing](./agent-write-capability-routing.md) —
  why these agents override `can_write?` instead of using the default.
