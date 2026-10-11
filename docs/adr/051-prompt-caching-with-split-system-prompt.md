# ADR-051: Prompt caching with a split system prompt

**Date**: 2026-10-11
**Status**: Proposed

## Context

Every LLM call re-sent the full system prompt, tool definitions and conversation history. The system prompt also embedded values that change on every call (current time; for the Leader agent also site, page and user information), which prevented both Anthropic's explicit prompt caching and the automatic prefix caching of OpenAI, Azure OpenAI, Gemini and OpenAI-compatible servers from matching.

## Decision

- Add the value object `RedmineAiHelper::LlmClient::Instructions(fixed, variable)`. `BaseAgent#system_prompt` and `LeaderAgent#system_prompt` return it; the variable values (time, site/page/user context) move into separate templates (`base_agent/current_time`, `leader_agent/system_prompt_context`). Prompt wording is unchanged; only positions move.
- `BaseProvider#apply_instructions` joins both parts (`Instructions#to_s`) into one system message and adds no cache markers, so non-Anthropic providers receive a single system message with the variable part at the end.
- `AnthropicProvider` overrides it: when the profile's `prompt_caching_enabled` (new boolean column, default true) is set, it calls `chat.with_caching` (automatic breakpoint covering tools and conversation) and sends the fixed part as its own system block with `cache_until_here: true`, followed by the variable block. No TTL is given (provider default of 5 minutes). Errors are not rescued or retried.
- Langfuse generations record the total input (`input + cache_read + cache_write`) as `promptTokens` and the cache breakdown in the generation `metadata` (`cache_read_input_tokens`, `cache_creation_input_tokens`). `usageDetails` is not used, because Langfuse would add its entries together and count cached tokens twice.

## Consequences

- Positive: lower cost and latency for Anthropic; longer stable prefixes for providers with automatic caching.
- Negative: any code that treats `system_prompt` as a String must call `to_s`.
- Negative: the Anthropic request depends on RubyLLM 2.1's top-level `cache_control` support.

## Alternatives Considered

- `with_provider_options` / raw `cache_control`: duplicates what RubyLLM already abstracts.
- Automatic breakpoint only: nothing is cached before the variable part, so different questions do not share the prefix.
- Two system messages for every provider: some OpenAI-compatible servers accept only one system message.
- Extending the langfuse gem to send `usageDetails`: depends on gem internals and double-counts cached tokens.
