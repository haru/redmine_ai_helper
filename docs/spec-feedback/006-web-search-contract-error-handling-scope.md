# SF-006: Web search contract accepted cut-off answers and rescued every error in the agent

**Date**: 2026-10-12
**Feature**: specs/071-web-search-citations (branch `feature/071-web-search-citations`)
**Artifact**: contracts/web-search-agent.md (`perform_task` steps 6 and 9)
**Category**: convention-unknown
**Related**: None

## Feedback

A local review (`/speckit-review-run`) found that truncated web search answers (`pause_turn` after RubyLLM's continuations, `max_tokens`, `content_filter`) were returned as success, and that the rescue turned plugin-internal errors (e.g. an invalid citation) into error responses only the leader LLM saw. The user approved fixing all findings ("全て修正して"), which required changing the contract (code side: CRF-014).

## What the AI Wrote

```
6. response = chat.ask(task). When the chat stops waiting for input, raise with the existing message.
9. Exceptions in 3–8 are logged with ai_helper_logger.error and TaskResponse.create_error(e.message) is returned (same as the existing BaseAgent#dispatch).
```

## Correction

Step 6 now also raises when `finish_reason` is `:max_tokens`, `:content_filter` or (after RubyLLM's automatic continuations) `:pause_turn`; a nil finish reason is not treated as truncation. Step 9 limits the error response to step 6 (provider request, waiting, truncation), logs provider and model, and lets exceptions from steps 3, 4 and 7 (plugin code, invalid citation values) propagate to `Llm#chat`.

## Root Cause

The AI copied the existing `BaseAgent#dispatch` error handling into the contract as "the same treatment" without checking whether the first server-side tool introduces new failure modes. It did not read RubyLLM 2.1's `Protocols::Anthropic#complete` (bounded `pause_turn` continuation) or `Message#finish_reason` predicates, and it scoped the rescue to "steps 3–8" by convenience rather than to the external call.

## Prevention

When a spec adds a new kind of LLM call (server tools, new protocol), list the library's completion outcomes for it (finish reasons, continuation limits) and state which count as failure. When a contract says "errors become an error response", name the exact calls covered; code that validates or converts the result is excluded.

**Promoted to**: Not yet
