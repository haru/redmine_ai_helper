# CRF-014: Truncated web search answers counted as success, and the rescue hid plugin errors

**Date**: 2026-10-12
**Source**: Local AI review (`/speckit-review-run`, errors agent)
**Feature**: branch `feature/071-web-search-citations`
**Files**: lib/redmine_ai_helper/agents/web_search_agent.rb, specs/071-web-search-citations/contracts/web-search-agent.md, test/unit/agents/web_search_agent_test.rb
**Category**: error-handling
**Related**: CRF-003, CRF-009

## Feedback

1. `WebSearchAgent#search` only checked `chat.waiting?`. RubyLLM 2.1 continues an Anthropic `pause_turn` at most 8 times and then returns what it has with `finish_reason: :pause_turn`; `:max_tokens` and `:content_filter` were also accepted. A partial research result and partial citations were returned as success, with nothing logged.
2. `rescue => e` wrapped the whole method, including the citation conversion. An `ArgumentError` from `WebCitation` (a provider returning an invalid title) or a `NoMethodError` in plugin code became an "Error: ..." step result that only the leader LLM saw, and the log line had no provider/model context.

## Original Code

```ruby
response = chat_instance.ask(task)
raise_if_waiting(chat_instance)
@citations.concat(response.citations.filter_map { |citation| WebCitation.from_ruby_llm(citation) })
TaskResponse.create_success response.content
rescue => e
  ai_helper_logger.error "error: #{e.full_message}"
  TaskResponse.create_error e.message
```

## Fix

Added `raise_if_incomplete(response)` (raises on `max_tokens?`, `content_filtered?` or `:pause_turn`; a nil finish reason is accepted because some OpenAI-compatible servers omit it). The rescue now covers only `ask`, `raise_if_waiting` and `raise_if_incomplete`, and logs the provider class and model. Citation conversion and other plugin code propagate to `Llm#chat`. Contract `web-search-agent.md` steps 6 and 9 were updated. Tests drive each finish reason, the nil reason, and the propagated `ArgumentError`.

## Root Cause

The code followed the existing `BaseAgent#dispatch` pattern (rescue everything, return an error response), which the contract also prescribed. That pattern predates server-side tools: it never had to consider a response that completes without an exception but is cut off. The AI did not read RubyLLM's `pause_turn` handling or `Message#finish_reason` predicates when adding the first server tool, and it scoped the rescue to the method by habit rather than to the call that can fail for external reasons.

## Prevention

- After any LLM call whose answer is used as a result, check `finish_reason` explicitly (`max_tokens?`, `content_filtered?`, provider-specific reasons such as `:pause_turn`) and raise on a cut-off answer; do not rely on `waiting?` alone.
- A `rescue` that converts errors into a result value must wrap only the external call (the provider request). Code that validates or converts its result stays outside, so invariant violations surface.

**Promoted to**: Not yet
