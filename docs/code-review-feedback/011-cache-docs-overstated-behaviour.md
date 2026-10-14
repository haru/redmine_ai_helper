# CRF-011: Prompt caching docs and comments described behaviour more narrowly or strongly than the code

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/070-prompt-caching`
**Files**: README.md, lib/redmine_ai_helper/base_agent.rb, langfuse_util/langfuse_wrapper.rb, llm_client/instructions.rb, assistant.rb, wiki/pages/llm-provider-layer.md
**Category**: doc-comment
**Related**: CRF-005, CRF-007

## Feedback

The comment reviewer found:
- README and the Langfuse comments implied cache token metadata is Anthropic-only, but RubyLLM's Chat Completions protocol returns `cache_write = 0`, so OpenAI/Azure/compatible generations also get the metadata; "other providers cache automatically" is false for many OpenAI-compatible servers.
- `BaseAgent#system_prompt` said the fixed part is "identical between calls", but it varies by agent, project, language and settings.
- The wiki said total input is stored in metadata; it is stored as `promptTokens`.
- The `Instructions` doc omitted that Anthropic with caching disabled also receives the joined string.
- `Assistant#instructions=` was documented with the new type although it only stores the value and never reaches the chat.

## Original Code

```ruby
# The fixed part is identical between calls; the variable part holds the
# current time so that the fixed part can be cached by the provider.
```

## Fix

Rewrote each statement to match the code and the RubyLLM 2.1.0 source (see the files above); documented that `Assistant#instructions=` does not re-apply the prompt.

## Root Cause

The AI wrote docs from the feature's intent (Anthropic caching) rather than from what the shared code paths do for every provider, and did not read the RubyLLM token mapping for the non-Anthropic protocols before describing which providers report cache counts.

## Prevention

Before documenting what a shared code path records or sends, check its behaviour for every provider/protocol that reaches it (read the library's parse code), and phrase guarantees with their actual scope ("per agent/project/locale", "whenever RubyLLM returns non-nil").

**Promoted to**: AGENTS.md
