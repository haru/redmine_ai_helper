# CRF-016: Web search docs overstated OpenAI support and omitted the Think-model case

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, comments agent)
**Feature**: branch `feature/071-web-search-citations`
**Files**: lib/redmine_ai_helper/llm_provider.rb, README.md, config/locales/en.yml, config/locales/ja.yml, wiki/pages/llm-provider-layer.md, wiki/pages/multi-agent-architecture.md, docs/adr/052-web-search-via-dedicated-agent.md, lib/redmine_ai_helper/agents/web_search_agent.rb, lib/redmine_ai_helper/llm.rb
**Category**: doc-comment
**Related**: CRF-005, CRF-007, CRF-011

## Feedback

- Comments, README, locale text, wiki and ADR-052 said "OpenAI supports web search" without qualification. In RubyLLM 2.1, `Providers::OpenAI#protocol_for` sends the search-preview models and model ids matching `audio`/`realtime` to Chat Completions, which has no `web_search` alias, so `with_provider_tools(:web_search)` raises `UnsupportedServerToolError` on those models while the settings page shows no warning.
- The README and wiki gave the main profile as the only condition, but for `use_think_model` steps the Think provider decides, and an unsupported Think provider answers without searching (documented only in the ADR).
- Smaller: `Llm#chat`'s `@return` did not mention the citations; the "only the task is sent" comment omitted the system prompt; README promised a title for every source.

## Original Code

```ruby
# LLM types whose provider-side web search tool RubyLLM supports.
WEB_SEARCH_LLM_TYPES = [ LLM_OPENAI, LLM_ANTHROPIC, LLM_GEMINI ].freeze
```

## Fix

Qualified the OpenAI statement (Responses API models only) in the constant comment, YARD, README, en/ja locale text, the settings contract, the wiki and ADR-052; documented the Think-model behaviour and Gemini's redirect URLs in README/wiki; corrected the `Llm#chat` and `WebSearchAgent#perform_task` comments. No behaviour change for the OpenAI model check (the support decision stays by LLM type).

## Root Cause

The AI read RubyLLM's `server_tool_aliases` for the OpenAI provider's default (Responses) protocol and generalized it to the whole provider, without reading `protocol_for`, which routes some models elsewhere. CRF-005/011 require checking every protocol that reaches a shared path; the AI checked providers, not per-model protocol routing. The Think-model nuance was written into the ADR but not propagated to user-facing docs.

## Prevention

When documenting what a provider supports through RubyLLM, read the provider's `protocol_for`/`resolve_protocol` and state support per protocol (and therefore per model family), not per provider. A behaviour condition documented in an ADR must also appear in every user-facing description of the same feature (README, wiki, locale help text).

**Promoted to**: Not yet
