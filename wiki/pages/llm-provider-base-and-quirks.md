---
title: LLM Provider Base Class & Quirks
type: component
sources: [S009, S021, S037, S039, S042]
updated: 2026-11-21
---

# LLM Provider Base Class & Quirks

`BaseProvider` and per-provider gotchas. Split from [LLM Provider Layer](./llm-provider-layer.md).

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

## Related

- [LLM Provider Layer](./llm-provider-layer.md) — the main page.
