# CRF-018: Repeated expressions and a dead initial value in the web search change

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, simplify agent)
**Feature**: branch `feature/071-web-search-citations`
**Files**: lib/redmine_ai_helper/base_agent.rb, lib/redmine_ai_helper/agents/web_search_agent.rb, lib/redmine_ai_helper/chat_channel/message_handler.rb, lib/redmine_ai_helper/llm.rb
**Category**: readability
**Related**: CRF-012

## Feedback

- `think_llm_provider || @llm_provider` appeared three times (`BaseAgent#think_chat`, `#build_think_assistant`, `WebSearchAgent#perform_task`).
- `user&.language.presence || Setting.default_language` was repeated in `MessageHandler#citations_text`, `#guidance` and `#process_question`.
- `Llm#chat` initialized `citations = []` before `begin`, a value never read because both the body and the rescue assign it.

## Original Code

```ruby
provider = option[:use_think_model] ? (think_llm_provider || @llm_provider) : @llm_provider
...
locale = user&.language.presence || Setting.default_language
```

## Fix

Added `BaseAgent#think_or_main_provider` and `MessageHandler#reply_locale(user)` and used them at every site; removed the dead initial assignment and documented why the rescue resets `citations`.

## Root Cause

New code copied an existing expression instead of extracting it when it became the third occurrence, and the initial value was added defensively without checking that all paths assign it.

## Prevention

When adding the third copy of the same expression, extract a named method and replace every copy in the same change. Do not add defensive initial values to locals that every path assigns; if a later reassignment matters, comment why.

**Promoted to**: Not yet
