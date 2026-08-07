---
title: Multi-Agent Architecture
type: concept
sources: [S005, S008, S009, S016]
updated: 2026-08-07
---

# Multi-Agent Architecture

The plugin answers a chat request with a hierarchy of agents over RubyLLM: a
`LeaderAgent` plans and routes, and specialized worker agents (IssueAgent,
WikiAgent, …) do the domain work — all subclasses of `BaseAgent` (S005).

> Provenance note: this page's structural claims come from the DeepWiki
> auto-generated architecture doc (S005). Method *signatures* are described by
> role rather than copied verbatim, since that source is AI-generated.

## Request flow

```
AiHelperController  →  RedmineAiHelper::Llm  →  LeaderAgent  →  worker agents  →  LLM provider
```

- `AiHelperController` handles the HTTP request; **custom commands are expanded
  before** the request reaches the agent layer (S005). See
  [Custom Commands](./custom-commands.md).
- `Llm` is the entry-point orchestrator: it creates the Langfuse trace and
  coordinates the agents (S005). Every request is traced for observability (S005).
- `LeaderAgent` generates a **JSON-defined goal** (intent + required steps),
  streams a "Planning…" status, then sequences the specialized agents and
  aggregates their results into the final answer (S005). Backstories and
  goal-generation prompts come from YAML templates in
  `assets/prompt_templates/`, externalized for localization (S005).

## Agents

- All agents inherit `BaseAgent`, which centralizes LLM communication, tool
  registration, and Langfuse integration (S005). See
  [BaseAgent LLM Calls](./base-agent-llm-calls.md) for its call styles.
- **Auto-registration**: subclassing hooks Ruby's `inherited` callback, so
  agents self-register with no manual dependency wiring (S005).
- Conversation state (message history + state) lives in a **`ChatRoom`** context
  for the duration of a conversation (S005).
- **Write-capable steps are guarded structurally, not by prompt convention**:
  each planned step carries a `requires_write` flag, and `LeaderAgent` checks
  it against the assigned agent's `can_write?` immediately before dispatch —
  routing itself still relies on backstory wording, not this check. See
  [Agent Write-Capability Routing](./agent-write-capability-routing.md) (S016).

## Tool system

Agents touch Redmine **only** through tools (S005). A `BaseTools` DSL declares
functions that compile into `RubyLLM::Tool` subclasses, an agent exposes them by
overriding `available_tool_providers`, and read-only mode filters out tools
declared `write: true` (S005, S008). Full detail on the
[Tool System](./tool-system.md) page.

## Provider-agnostic LLM layer

An `LlmProvider` factory builds provider-specific clients with per-profile API
key isolation, reading credentials from `AiHelperModelProfile`; OpenAI,
Anthropic, Gemini, Azure OpenAI, and OpenAI-compatible services are supported
(S005, S009). RubyLLM is initialized globally in `init.rb` (S005). Full detail —
resolution paths, provider quirks, structured output — on the
[LLM Provider Layer](./llm-provider-layer.md) page. See also
[BaseAgent LLM Calls](./base-agent-llm-calls.md) and
[Think Model](./think-model.md).

## Streaming & observability

Responses stream over **SSE** via `ActionController::Live` and the
`AiHelper::Streaming` concern; the `LeaderAgent` streams intermediate status and
final results (S005). SSE requires `ActionController::Live`, which is not
compatible with all Rack middleware (S005) — behind Nginx it also needs specific
proxy settings ([Nginx SSE Proxy](./nginx-sse-proxy.md)).

## Related

- [Plugin Overview](./plugin-overview.md) · [MCP Integration](./mcp-integration.md)
- [Chat Channel Gateway Architecture](./chat-channel-gateway-architecture.md) —
  an alternate entry point that reuses this same agent stack.
- [Agent Write-Capability Routing](./agent-write-capability-routing.md) — the
  `requires_write`/`can_write?` guard mentioned above.
