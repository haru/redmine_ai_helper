---
title: BaseAgent LLM Calls
type: component
sources: [S003, S005, S009, S021]
updated: 2026-08-20
---

# BaseAgent LLM Calls

`BaseAgent` (the base class of every agent — see
[Multi-Agent Architecture](./multi-agent-architecture.md)) has **two distinct
ways** of calling an LLM, and the difference matters for any feature that wants
to swap the model (S003).

The concrete provider behind these calls is provider-agnostic: an `LlmProvider`
factory builds a provider-specific client — OpenAI, Anthropic, Gemini, Azure
OpenAI, or OpenAI-compatible — with per-profile API-key isolation, reading
credentials from an `AiHelperModelProfile` (S005). The factory's
`get_think_llm_provider` returns **nil** when the think model is unconfigured —
that nil is precisely what makes `think_chat` delegate to `chat` (S009). Full
detail on the [LLM Provider Layer](./llm-provider-layer.md) page.

## The two call styles

1. **`chat` (externally managed)**: creates a fresh `RubyLLM::Chat` instance on
   every call, the caller passes messages explicitly, and the caller owns the
   conversation history. Health-report generation/comparison, issue reply
   drafting, and `LeaderAgent` itself all use *only* this style (S003).
2. **`@assistant` (internally managed)**: the `RubyLLM::Chat` instance keeps its
   own `@messages` history; used via `add_message` + `perform_task` for
   multi-turn, tool-using conversations — e.g. when `ChatRoom` dispatches a task
   to a sub-agent (S003).

## Think-model hook

For the [Think Model](./think-model.md), `BaseAgent` holds two providers and
adds one method (S003):

```
@llm_provider          # normal model (existing)
@think_llm_provider    # think model (added)

chat(messages)         # calls @llm_provider (unchanged)
think_chat(messages)   # calls @think_llm_provider; delegates to chat when unset
```

Because every think-model target task already uses `chat()` (one-shot),
`think_chat()` alone covers the feature — no `@think_assistant` or shared-chat
machinery was needed (S003). This is the start of an `effective_llm_provider`
pattern for future dynamic switching (S003).

## Swapping a provider from the caller

`@llm_provider` is exposed as an `attr_accessor`, so a caller can hand an agent a
differently-configured provider after construction instead of extending the
agent's params API — this is how completion calls get their short-timeout,
no-retry provider without touching `BaseAgent`
([Completion Request Timeout Policy](./completion-request-timeout-policy.md), S021).

## Gotcha: `with_model` does not switch providers

`RubyLLM::Chat#with_model(model_id)` swaps the model in place and returns `self`,
but it **only changes the model ID — not the provider's API config** (endpoint,
API key, auth method) (S003). So a "share one `@chat` instance and call
`with_model` per turn" design **fails** whenever the normal and think models are
on different providers (e.g. OpenAI ↔ Anthropic) — that approach was rejected
for exactly this reason (S003).

Consequently, applying the think model to the tool-using `@assistant` loop is
**unsolved and out of scope**: it would require switching providers *and*
sharing conversation history at once, with no good design yet (S003).

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) · [Think Model](./think-model.md) · [Plugin Overview](./plugin-overview.md)
