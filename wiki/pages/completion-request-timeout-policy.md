---
title: Completion Request Timeout Policy
type: decision
sources: [S021]
updated: 2026-08-20
---

# Completion Request Timeout Policy

Inline-completion LLM calls run with a **short timeout and zero retries**, while
every other AI feature keeps RubyLLM's defaults (S021). ADR-018 records the
policy; this page records why and how.

## The problem: RubyLLM defaults are hostile to completion

RubyLLM 1.16.0 defaults to `request_timeout: 300` and `max_retries: 3`
(`configuration.rb`), and its retry middleware targets
`IDEMPOTENT_METHODS + [:post]` **including `Faraday::TimeoutError`**
(`connection.rb`) (S021). A single inline-completion request against a slow
backend can therefore occupy an application-server worker for
300 s × 4 ≈ **20 minutes** (S021). Combined with the client never aborting stale
`fetch` calls (see
[Inline Completion Request Flow](./inline-completion-request-flow.md)), this
starved both the browser's per-origin connection pool and the worker pool, so
unrelated actions such as saving an issue hung for minutes (S021).

## Decision

Completion calls use `request_timeout` from the configured completion timeout
(default 30 s, accepted range 1–600) and `max_retries: 0` — POST retries are
eliminated outright (S021). The scope is deliberately **completion only**; other
AI features are untouched (S021).

## Injection path

`RubyLLM.context` `dup`s the global configuration before yielding it
(`ruby_llm.rb`), so a per-context override cannot leak into other features, and
`Context#config` is a public `attr_reader`, allowing the override to be applied
*after* `build_context` (S021). The chosen path keeps the existing abstractions:

1. `BaseProvider#initialize` takes an optional `request_options:`
   (`{ request_timeout:, max_retries: }`).
2. `BaseProvider#context` applies it to `context.config` after `build_context` —
   **all five provider subclasses stay unchanged** (S021).
3. `LlmProvider.get_llm_provider` / `provider_for_profile` pass it through.
4. `Llm#generate_text_completion` / `#generate_wiki_completion` swap
   `agent.llm_provider` using the pre-existing `attr_accessor`, so `BaseAgent`
   itself needs no change (S021). See
   [BaseAgent LLM Calls](./base-agent-llm-calls.md).

## Which exception surfaces

RubyLLM has **no timeout-specific error class** — `ruby_llm/error.rb` covers HTTP
statuses only, and the error middleware converts responses, not transport
exceptions (S021). With retries disabled, `Faraday::TimeoutError` propagates raw
(connection-establishment failure surfaces as `Faraday::ConnectionFailed`)
(S021). Both completion agent methods rescue it, log at **warn** level with
context type / project / elapsed seconds, and return `""`; other exceptions keep
the existing error-level log + `""` behaviour (S021).

## Alternatives rejected

- **Global `RubyLLM.configure` change** — would shorten timeouts for every AI
  feature, contradicting the completion-only scope (S021).
- **Branching inside each provider's `build_context`** — the same change
  scattered across five files (DRY) (S021).
- **A provider option on `BaseAgent`'s params** — widens the agent framework's
  public API when `attr_accessor :llm_provider` already suffices (YAGNI) (S021).
- **Ruby-level `Timeout.timeout`** — risks corrupting `Net::HTTP` socket state;
  Faraday's native `options.timeout` is used instead (S021).

## Related

- [Inline Completion Request Flow](./inline-completion-request-flow.md) ·
  [LLM Provider Layer](./llm-provider-layer.md) ·
  [BaseAgent LLM Calls](./base-agent-llm-calls.md) ·
  [Issue AI Features](./issue-ai-features.md)
