---
title: Prompt Caching & Split System Prompt
type: decision
sources: [S043]
updated: 2026-10-11
---

# Prompt Caching & Split System Prompt

Feature 070 / ADR-051 cut LLM cost and latency by making the stable prefix of
every request cacheable. Only **Anthropic** profiles get explicit cache
markers; other providers get a better-ordered prompt and rely on their own
automatic prefix caching (S043).

## How Anthropic is cached

- Two breakpoints (Anthropic's limit is 4): `chat.with_caching` adds an
  automatic top-level `cache_control` that follows the end of the conversation
  across repeated tool calls, and the fixed part of the system prompt is sent
  via `with_instructions(fixed, cache_until_here: true)` as its own system
  block, with the variable part as a second block (S043).
- Both are needed: the automatic breakpoint alone writes at the request tail, so
  nothing before the variable time/context is shared between *different*
  questions; the explicit one alone does not cache history across tool-call
  rounds (S043).
- No TTL is passed (Anthropic default, 5 minutes). Cache errors are not
  rescued or retried (S043).
- Public RubyLLM 2.1 API only — no raw `cache_control` or `with_provider_options` (S043).
- Applied in `AnthropicProvider`'s instructions step, so every path that builds
  a chat (agents, think model, `FileTools`, vector analyzer, connection test)
  is covered; Slack/Discord go through the same agent path (S043).

## Why only Anthropic

A `cache_until_here` system message makes RubyLLM's Responses protocol (OpenAI /
compatible) emit cache breakpoints, and some OpenAI-compatible servers reject
two system messages. So `BaseProvider` joins both parts into **one** system
string with no markers (S043).

## Split system prompt

- `LlmClient::Instructions(fixed, variable)` (`Data.define`) is returned by
  `BaseAgent#system_prompt` and `LeaderAgent#system_prompt`; `#to_s` joins the
  parts with a blank line. A delimiter-in-string design was rejected because
  prompt text could contain it, and extra `create_chat` keywords or a second
  `system_prompt_parts` method would let overrides drift apart (S043).
- Variable values moved into separate templates: `base_agent/current_time` and
  `leader_agent/system_prompt_context`. Wording is unchanged — only positions
  move; time capture timing and `iso8601` format are unchanged (S043).
- `Instructions.coerce` accepts nil, String, or `Instructions` and raises
  `ArgumentError` otherwise; code treating `system_prompt` as a String must
  call `to_s` (S043).

## Setting

`ai_helper_model_profiles.prompt_caching_enabled` (boolean, default true, so
existing rows are enabled). The checkbox is shown only for Anthropic profiles;
copying a profile copies it via `dup`. It is per-profile, not global (S043).

## Langfuse

`promptTokens` records `input + cache_read + cache_write` (RubyLLM 2.1
normalizes `input` to exclude cache across protocols); the breakdown goes in
generation `metadata` (`cache_read_input_tokens`, `cache_creation_input_tokens`).
`usageDetails` is not used: Langfuse sums its entries and would double-count
cached tokens, and the langfuse gem 0.1.1 cannot send it anyway (S043).

## Related

[LLM Provider Layer](./llm-provider-layer.md) ·
[BaseAgent LLM Calls](./base-agent-llm-calls.md) ·
[RubyLLM 2.1 Migration](./ruby-llm-2-1-migration.md)
