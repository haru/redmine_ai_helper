# CRF-022: Progress reporter rescued every StandardError from the adapter and trusted its return value

**Date**: 2026-10-13
**Source**: Local AI review (`/speckit-review-run`, errors and types agent)
**Feature**: branch `073-chat-channel-progress`
**Files**: lib/redmine_ai_helper/chat_channel/progress_reporter.rb, lib/redmine_ai_helper/chat_channel/base_adapter.rb, lib/redmine_ai_helper/chat_channel/adapters/slack_adapter.rb, lib/redmine_ai_helper/chat_channel/adapters/discord_adapter.rb, lib/redmine_ai_helper/agents/leader_agent.rb
**Category**: error-handling
**Related**: CRF-014, CRF-009, CRF-003

## Feedback

1. `ProgressReporter#guarded` rescued `StandardError` around whole adapter methods (destination lookup, payload building, `Handle.new`, `JSON.parse`). A `NoMethodError` or `NameError` inside an adapter only produced one log line and silently disabled progress, although ADR-054 said bugs were not rescued.
2. The value returned by `post_progress` was not checked. A nil or non-`Handle` return counted as success, so every later line would post a new message and none would be deleted.
3. The failure log did not name the posted message, so a message left behind could not be found.
4. `LeaderAgent` accepted any `progress_proc`; a non-callable value failed later with a `NoMethodError` that `Llm#chat` turned into the answer text.

## Original Code

```ruby
def guarded(action)
  yield
  true
rescue StandardError => e
  ai_helper_logger.error "chat channel: failed to #{action} progress message on ..."
  false
end
# call:
posted = guarded("post") { @handle = @adapter.post_progress(...) }
```

## Fix

`BaseAdapter#progress_errors` (default `[]`) lists what an adapter's progress calls may raise; Slack and Discord return their API errors, `JSON::ParserError` and `NETWORK_ERRORS`. `guarded` rescues only those. `call` raises `TypeError` (logged, disables progress) when `post_progress` does not return a `Handle`. The log line includes the message id and channel once a message exists. `LeaderAgent#initialize` raises `ArgumentError` for a non-callable `progress_proc`. Tests cover each branch, and a contract test checks that every adapter supporting progress implements the whole interface.

## Root Cause

The AI copied the broad rescue of the previous feature (ADR-053) and the contract's "StandardError from the adapter call" wording, and scoped it to the method rather than to the failing external call, the same habit as CRF-014. It trusted a YARD-only return contract and did not apply the CRF-009 rule (validate types at the boundary) to the adapter interface.

## Prevention

- A rescue that turns errors into a "failed" result lists the error classes the external call can raise (API, network, parse) and never `StandardError`; the owner of the call (the adapter) declares them.
- A value returned across an adapter or plugin boundary is checked with `is_a?` where it is first used, and a violation raises; do not rely on the YARD `@return` alone.
- Log lines for a failed operation on a created resource name that resource's id.

**Promoted to**: AGENTS.md
