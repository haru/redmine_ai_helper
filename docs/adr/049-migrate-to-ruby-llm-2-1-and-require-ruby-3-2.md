# ADR-049: Migrate to RubyLLM 2.1 and require Ruby 3.2 or later

**Date**: 2026-10-11
**Status**: Proposed

## Context

The plugin depended on RubyLLM 1.16. Two problems motivated an upgrade:

- Issue #480: tool calling fails with gpt-6 series models on the Chat Completions API, because RubyLLM 1.x cannot call them with reasoning enabled there.
- Issue #491: RubyLLM 1.x logs "legacy acts_as API is deprecated" warnings.

RubyLLM 2.1 fixes both, but its gemspec requires Ruby 3.2 or later, so Ruby 3.1 can no longer be supported. RubyLLM 2.x also changes the API surface the plugin uses (`after_message`, `message.tokens`, `with_end_user`, the Tool DSL `parameters`, removal of `RubyLLM::Content` and `Model::Info`) and selects the OpenAI API protocol per provider.

## Decision

- Depend on `ruby_llm ~> 2.1.0` and drop `ruby_llm-mcp` (see ADR-050).
- Require Ruby 3.2 or later. Ruby 3.1 support ends; CI no longer tests it. The plugin does not add its own Ruby version check, because Bundler already fails dependency resolution with the Ruby requirement in its message.
- Add `gem "json", "< 3"` unconditionally. The RubyLLM upgrade guide asks for JSON 2 on Rails versions before 8.1.4; Redmine 6.0 and 6.1 use Rails 7.2. A conditional on the Rails version would be fragile inside Redmine's Gemfile evaluation, and json 2.x works on every supported Ruby.
- Do not choose between the Chat Completions API and the Responses API in the plugin. No `protocol:` option or provider options are passed; RubyLLM's own selection applies. OpenAI therefore uses the Responses API, which resolves Issue #480. OpenAI-compatible profiles use the same `:openai` provider and also get the Responses API.
- Switch Azure OpenAI to RubyLLM's `:azure` provider (`azure_api_base` / `azure_api_key`). Model profile fields are unchanged. The provider builds the URL from the configured base URI and picks the protocol per deployment.
- Keep the Langfuse integration behaviour unchanged by porting it to `after_message` and `message.tokens`.

## Consequences

- Positive: Issue #480 and Issue #491 are resolved without plugin-side workarounds; protocol selection follows RubyLLM and needs no maintenance here.
- Negative: Ruby 3.1 users must upgrade Ruby or stay on the previous plugin version.
- Negative: OpenAI-compatible servers that do not implement the Responses API (many Ollama, vLLM and LM Studio setups) stop working.
- Negative: the plugin still touches RubyLLM internals in one place (`append_to_model_registry` writes to the registry's `@models`), which may need rework on later RubyLLM releases.

## Alternatives Considered

- Keep RubyLLM 1.x and special-case gpt-6 models: leaves Issue #491 open and keeps a plugin-side workaround for a library defect.
- Force `protocol: :chat_completions` for OpenAI-compatible profiles: preserves compatibility with servers lacking the Responses API, but means the plugin owns protocol selection. Rejected in favour of delegating to RubyLLM.
- Keep Azure on the `:openai` provider: would send Responses API requests to deployments or API versions that do not support them.
- Conditional `json` constraint by Rails version: rejected as fragile (see Decision).
