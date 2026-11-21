---
title: MCP Tool Call Failures
type: component
sources: [S065]
updated: 2026-11-21
---

# MCP Tool Call Failures

Split from [MCP Integration](./mcp-integration.md). Behavior of RubyLLM 2.2 that
the plugin relies on and does not wrap (S065, ADR-074).

A failing MCP tool call does not stop the chat. A transport failure, HTTP 429, a
5xx response or a stdio server exit becomes the tool's result for the model
(`The <server> MCP server failed: ...`), and the chat goes on (S065). The server
then sits out for a while; calls during that time return `can't be reached right
now` without contacting it (S065).

A 4xx refusal other than 429, and a failure to list the tools, still raise
(S065). `McpTools.generate_tool_classes` returns `mcp_client.tools` and lets
connection errors reach the caller.

The plugin adds no `rescue` around tool calls. `McpToolCallFailureTest` pins the
behavior with a stdio server that exits during `tools/call`
(`test/support/mcp/exits_on_tool_call_server.rb`), run through the real
conversation loop with `RubyLLM::TestHelper` (S065). The 4xx refusal has no test
because it needs an HTTP server and would only exercise RubyLLM.
