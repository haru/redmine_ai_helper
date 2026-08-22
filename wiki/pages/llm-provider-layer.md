---
title: LLM Provider Layer
type: component
sources: [S009, S021]
updated: 2026-08-20
---

# LLM Provider Layer

The provider layer isolates the rest of the plugin from which LLM vendor is in
use. `RedmineAiHelper::LlmProvider` is the factory (S009).

> Provenance: from the DeepWiki auto-generated doc (S009); the provider
> subclasses and `configure_ruby_llm` / `create_chat` methods match the
> project's documented structure.

## Factory & resolution paths

`LlmProvider` resolves a provider from the active `AiHelperModelProfile` via
three entry points (S009):

- `get_llm_provider` — the default, from the global `model_profile`.
- `get_vector_llm_provider` — the [vector model profile](./vector-search.md);
  **falls back to the default** when `use_vector_model_profile` is false (S009).
- `get_think_llm_provider` — returns **nil** when the
  [think model](./think-model.md) is off/unconfigured, which is exactly the
  signal that makes `think_chat` fall back to normal `chat` (S009). See
  [BaseAgent LLM Calls](./base-agent-llm-calls.md).

Five provider types map to concrete classes: `OpenAiProvider`,
`AnthropicProvider`, `GeminiProvider`, `AzureOpenAiProvider`, and
`OpenAiCompatibleProvider` (S009).

## BaseProvider

All inherit `RedmineAiHelper::LlmClient::BaseProvider` (S009):

- **Thread-safe registration**: a `FETCH_MUTEX` guards model registration into
  RubyLLM's global registry; `model_in_registry?` gates
  `fetch_and_register_model!` so concurrent requests don't collide (S009).
- `context` returns a memoized `RubyLLM::Context` (after ensuring registration) (S009).
- `create_chat` builds a `RubyLLM::Chat`, applying instructions, tools,
  temperature, and any structured-output schema from the profile (S009).
- `embed` generates embeddings; `supports_structured_output?` reports native
  JSON-schema support (S009).
- **Per-call HTTP options**: `initialize` accepts an optional `request_options:`
  (`request_timeout` / `max_retries`) that `context` applies to `context.config`
  *after* `build_context`, and `get_llm_provider` / `provider_for_profile` pass
  it through. `RubyLLM.context` `dup`s the global config, so the override is
  caller-scoped and the five subclasses need no change (S021). Its only current
  user is [inline completion](./completion-request-timeout-policy.md).

## Provider quirks (gotchas)

- **Anthropic & Gemini** override `supports_user_identifier?` → **false**: they
  reject the `user` identifier field (S009).
- **OpenAI-Compatible** (e.g. Ollama): `create_chat` forces `provider: :openai`
  and `assume_model_exists: true` to bypass model-list validation on custom
  endpoints, and sets `openai_use_system_role = true` (S009).
- **Azure OpenAI**: deployment-based — `assume_model_exists: true`, with the
  endpoint taken from the profile's `base_uri` (S009).

## Configuration from the profile

`AiHelperModelProfile` supplies API keys/org IDs, base URIs, model names,
temperature, max tokens, and the embedding model (S009). The layer applies max
tokens, temperature, an optional user identifier (`apply_user_identifier` when
`send_user_id_enabled`), and an HTTP proxy into `RubyLLM::Configuration` at
context creation (S009). **API keys are per-profile and never mixed across
provider contexts** (S009). A separate `embedding_model` decouples embeddings
from the chat model for cost control (S009).

## Structured output (ADR-004)

Two-tier, for cross-provider reliability (S009): when
`supports_structured_output?` is true, the schema (`name` / `schema` / `strict`)
is passed natively via `chat.with_schema(schema)`; otherwise the schema is
injected into the prompt instead of calling the native API.

## Related

- [Multi-Agent Architecture](./multi-agent-architecture.md) ·
  [BaseAgent LLM Calls](./base-agent-llm-calls.md) ·
  [Think Model](./think-model.md) · [Vector Search](./vector-search.md) ·
  [Completion Request Timeout Policy](./completion-request-timeout-policy.md)
