# CRF-003: Errors swallowed or cached as empty results around MCP tools and structured output

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/069-ruby-llm-2-1-migration`
**Files**: lib/redmine_ai_helper/tools/mcp_tools.rb, util/mcp_server_loader.rb, llm_client/base_provider.rb, base_agent.rb, assistant.rb, test/unit/tools/mcp_tools_test.rb
**Category**: error-handling
**Related**: None

## Feedback

`McpTools` rescued every error and cached `[]` per server forever (RubyLLM's MCP client is now lazy, so connection errors arrive there), the agent had a second dead rescue, `supports_structured_output?` rescued everything and returned false, and a paused chat (MCP input request) returned an empty answer with no error.

## Original Code

```ruby
@mcp_tool_cache[name] ||= begin ... rescue => e; log; [] end
```

## Fix

Removed the cache and rescues so errors surface and a failed lookup is retried; passed `input_requests: false`; `BaseAgent`/`Assistant` raise when the chat is `waiting?`; removed the catch-all in `supports_structured_output?`. Tests now expect the errors.

## Root Cause

The AI preserved the pre-migration rescue-and-return-empty pattern when swapping the MCP client without re-checking where failures now occur, and without applying the AGENTS.md rule "NEVER implement fallback error handling". The tests only asserted the empty result, which locked in the fallback.

## Prevention

Do not write `rescue => e` that returns `[]`/`false`/nil or caches a failure. When replacing a client library, re-derive where errors are raised (eager vs lazy) and what states (paused, waiting) can yield an empty result. Tests must assert that errors propagate.

**Promoted to**: AGENTS.md
