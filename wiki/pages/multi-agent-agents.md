---
title: Multi-Agent Architecture: Agents
type: concept
sources: [S005, S016, S044]
updated: 2026-11-21
---

# Multi-Agent Architecture: Agents

The agent roster and their roles. Split from [Multi-Agent Architecture](./multi-agent-architecture.md).

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

- **Web search**: `WebSearchAgent` is the only agent that enables the provider's
  web search tool (`with_provider_tools(:web_search)`). It has no Redmine tools,
  receives only the content of its task, and is offered to the leader only when
  the `web_search_enabled` setting is on and the main model profile is OpenAI,
  Anthropic or Gemini. For `use_think_model` steps the Think provider decides;
  if it does not support web search, the step is answered without searching and
  yields no sources. An answer the provider cut off (`max_tokens`,
  `content_filter`, or `pause_turn` after RubyLLM's continuations) becomes an
  error response. Its sources flow `WebSearchAgent#citations` →
  `ChatRoom#citations` → `LeaderAgent#citations` → the `AiHelperMessage` that
  `Llm#chat` returns (ADR-052, S044). Search terms are chosen by the model.
  Details: [Web Search & Citations](./web-search-citations.md).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) — the main page.
