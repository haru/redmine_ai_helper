---
title: RubyLLM 2.1 Migration
type: decision
sources: [S042]
updated: 2026-10-11
---

# RubyLLM 2.1 Migration

Feature 069 moves the plugin from RubyLLM 1.16 to `~> 2.1.0`, drops `ruby_llm-mcp`, and requires Ruby 3.2+ (ADR-049, ADR-050). Choices below are from the research/plan (S042).

## Dependencies

- Gemfile: `ruby_llm ~> 2.1.0`, no `ruby_llm-mcp`, and an unconditional `json < 3` (Rails before 8.1.4 needs JSON 2; a Rails-version conditional was rejected as fragile) (S042).
- Ruby 3.1 is dropped (the gem needs `>= 3.2`); no plugin-side version check, Bundler's resolution error is enough. CI moves to 3.2 (S042).

## Chat API choice is left to RubyLLM

No `protocol:` option is passed. OpenAI and OpenAI-compatible profiles therefore use the Responses API (which fixes the gpt-6 tool-call Issue #480). Azure keeps Chat Completions except for newer GPT-5.x/6+ deployment names (S042).

> Consequence: OpenAI-compatible servers without a Responses API (many Ollama/vLLM/LM Studio setups) stop working. Forcing `protocol: :chat_completions` for them was rejected by the user (S042).

## Azure uses the `:azure` provider

`AzureOpenAiProvider` sets `azure_api_base` / `azure_api_key` and calls `chat(provider: :azure, assume_model_exists: true)`. The profile fields are unchanged. The provider derives the URL from `base_uri` and picks the auth header itself. Staying on `:openai` was rejected because it would force Responses API on every deployment (S042). See [LLM Provider Layer](./llm-provider-layer.md).

## External MCP: built-in client

- `McpServerLoader` calls `RubyLLM.mcp(name:, command: argv, env:)` for stdio and `RubyLLM.mcp(name:, url:, headers:)` for HTTP. stdio uses an argv array, so there is no shell string and spaces in args are safe (S042).
- `mcp.tools` returns `RubyLLM::Tool`-compatible objects that still go through `with_tools`. `with_mcp` was rejected because it would force a rework of `available_tool_classes` (S042).
- Connection happens lazily on the first `tools` call. Connection and tool-list failures propagate to the calling request; nothing is cached, so the next lookup retries. The old rescue-and-cache-`[]` behaviour was removed as a fallback (CRF-003).
- **Unsupported, skipped at validation with a logged warning**: `"type": "sse"` (the built-in client has only Streamable HTTP/stdio), and plain `http://` to a non-loopback host or a URL with `user:pass@`. The check calls the `:nodoc:` `RubyLLM::MCP::HTTP.secure?` rather than duplicating it, so tests cover loopback http, external http and https to catch drift (S042).

See [MCP Integration](./mcp-integration.md).

## 2.0 API changes absorbed

| Change | Handling (S042) |
|---|---|
| `on_end_message` → `after_message` (appends; also fires for tool results) | `setup_langfuse_callbacks` keeps the `role == :assistant` filter |
| `input_tokens`/`output_tokens` → `message.tokens` | records prompt/completion/total only |
| `RubyLLM::Content` removed | `extract_text_content` branch dropped; no compat stub |
| `with_params` → `with_end_user` | not used: the Responses protocol drops it, so `safety_identifier` is sent via `with_provider_options`; still skipped when `supports_user_identifier?` is false (ADR-049) |
| Tool DSL `params` → `parameters` | change in `BaseTools.define_function` |
| `with_instructions` replaces | unchanged: it is called once per chat |
| Structured output `content` is a String | no code change; parsers already accept Strings |

No new `rescue` is added for the new error classes (all are `RubyLLM::Error` subclasses). Issue #491's `acts_as` deprecation warning disappears with the upgrade, with no DB change (S042).

## Related

- [LLM Provider Layer](./llm-provider-layer.md) · [MCP Integration](./mcp-integration.md) · [Tool System](./tool-system.md) · [BaseAgent LLM Calls](./base-agent-llm-calls.md) · [Plugin Overview](./plugin-overview.md)
