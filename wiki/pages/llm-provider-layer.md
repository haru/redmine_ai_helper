---
title: LLM Provider Layer
type: component
sources: [S009, S021, S037, S039, S042, S043, S044]
updated: 2026-10-12
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
  The selection rule now lives in `AiHelperSetting#vector_llm_model_profile`,
  shared with the [embedding connection test](./embedding-connection-test.md) (S039).
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
  Temperature is applied only when set (`with_temperature(temperature) if
  temperature`), so a blank profile temperature sends none — see
  [Model Profile Temperature Is Optional](./model-profile-optional-temperature.md) (S037).
- `embed(text, embedding_model:)` generates embeddings; the keyword defaults to
  the saved `AiHelperSetting#embedding_model`, and an explicit nil/blank uses the
  provider default (S039); `supports_structured_output?` reports native
  JSON-schema support (S009).
- **Per-call HTTP options**: `initialize` accepts an optional `request_options:`
  (`request_timeout` / `max_retries`) that `context` applies to `context.config`
  *after* `build_context`, and `get_llm_provider` / `provider_for_profile` pass
  it through. `RubyLLM.context` `dup`s the global config, so the override is
  caller-scoped and the five subclasses need no change (S021). It is used by
  [inline completion](./completion-request-timeout-policy.md) and by the
  [embedding connection test](./embedding-connection-test.md) (10 s, no retries);
  `fetch_and_register_model!` now applies it too, so the model-list fetch honours
  the limit (S039).

## Provider quirks (gotchas)

- **Anthropic & Gemini** override `supports_user_identifier?` → **false**: they
  have no `safety_identifier` field, so no user ID is sent (S009). Other providers send the ID as `safety_identifier` via `with_provider_options`, because RubyLLM's OpenAI Responses protocol drops `with_end_user` (S042, ADR-049).
- **OpenAI-Compatible** (e.g. Ollama): `create_chat` forces `provider: :openai`
  and `assume_model_exists: true` to bypass model-list validation on custom
  endpoints, and sets `openai_use_system_role = true` (S009).
- **Azure OpenAI**: deployment-based — `assume_model_exists: true`, with the
  endpoint taken from the profile's `base_uri` (S009). Since RubyLLM 2.1 it uses
  `provider: :azure` with `azure_api_base`/`azure_api_key` instead of `:openai` (S042).
- **API style is left to RubyLLM** (no `protocol:` passed): OpenAI and
  OpenAI-compatible use the Responses API, which some compatible servers lack
  (S042). See [RubyLLM 2.1 Migration](./ruby-llm-2-1-migration.md).

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
  [Completion Request Timeout Policy](./completion-request-timeout-policy.md) ·
  [Embedding Connection Test](./embedding-connection-test.md) ·
  [Model Profile Temperature Is Optional](./model-profile-optional-temperature.md) ·
  [Prompt Caching](./prompt-caching.md)

## Prompt caching and split system prompt

`BaseProvider#apply_instructions` joins an `Instructions(fixed, variable)` value
into one system message with no cache markers; `AnthropicProvider` overrides it
to add `with_caching` and a cached fixed block when the profile's
`prompt_caching_enabled` is true (S043). Full decision on
[Prompt Caching & Split System Prompt](./prompt-caching.md).

## Web search support

`LlmProvider.web_search_supported?(llm_type)` is true for OpenAI, Anthropic and
Gemini, false for Azure OpenAI and OpenAI-compatible, and raises
`ArgumentError` for an unknown type. `BaseProvider#supports_web_search?` applies
it to the provider's profile. `create_chat` never adds the search tool;
only `WebSearchAgent` does (ADR-052, S044). See
[Web Search & Citations](./web-search-citations.md).

The check is by LLM type only. RubyLLM 2.1 routes OpenAI's search-preview
models and model ids matching `audio`/`realtime` to Chat Completions, which has
no `web_search` alias, so a web search step on those models raises
`UnsupportedServerToolError` and becomes an error response; the settings page
does not warn about them (S044).
