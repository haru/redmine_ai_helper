# ADR-050: Replace ruby_llm-mcp with RubyLLM's built-in MCP client

**Date**: 2026-10-11
**Status**: Proposed

## Context

The plugin used the `ruby_llm-mcp` gem to connect to external MCP servers configured in `config/ai_helper/config.json` (stdio, Streamable HTTP and SSE). RubyLLM 2.1 ships a built-in MCP client (`RubyLLM.mcp`) and `ruby_llm-mcp` is not used with RubyLLM 2.x. The built-in client supports stdio and Streamable HTTP only. Plain `http://` is accepted only for loopback hosts, and credentials in the URL are rejected (`RubyLLM::MCP::HTTP.secure?`).

## Decision

- `McpServerLoader` creates one `RubyLLM.mcp` instance per configured server. stdio servers receive an argv array (`[command, *args]`), so no shell is involved; http servers receive `url` and `headers`.
- Keep the existing per-tool mechanism: `McpTools.generate_tool_classes` returns `mcp.tools` (`RubyLLM::Tool`-compatible instances) and agents pass them to `with_tools`. `with_mcp` is not used, so `available_tool_classes`, `available_tools` and the backstory generation stay unchanged.
- SSE servers and plain HTTP to non-loopback hosts (or URLs with credentials) are unsupported. The loader logs a warning naming the server and skips it; other servers keep loading. The plugin does not implement its own SSE or plain-HTTP transport.
- The loader calls `RubyLLM::MCP::HTTP.secure?` instead of duplicating the policy, so the warning is raised at load time rather than at the first connection. That class is marked `:nodoc:` and is an internal API; tests cover loopback HTTP, external HTTP, credentials and HTTPS so that a change in RubyLLM is detected.
- `config.json` keeps its format. Connection and tool-listing failures are logged per server as before, leaving that server's agent without tools.

## Consequences

- Positive: one fewer dependency; argv arrays remove quoting problems with arguments containing spaces.
- Negative: administrators using SSE servers or plain HTTP to remote hosts must switch to Streamable HTTP over HTTPS (or a loopback proxy).
- Negative: dependence on one `:nodoc:` RubyLLM method.

## Alternatives Considered

- Custom transports for SSE or plain HTTP through RubyLLM's `transport` hook: rejected to avoid maintaining protocol code and weakening RubyLLM's transport-security policy.
- `with_mcp` on the chat: rejected because it resolves tools dynamically inside `Chat#tools`, which would require reworking the agent tool pipeline.
- Defining a `RubyLLM::MCP` subclass per server: unnecessary because `RubyLLM.mcp` builds the same thing inline.
