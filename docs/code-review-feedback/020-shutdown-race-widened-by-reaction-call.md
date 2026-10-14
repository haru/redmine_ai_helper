# CRF-020: A slow reaction call between the shutdown check and the queue push lost messages

**Date**: 2026-10-13
**Source**: Local AI review (`/speckit-review-run`, code/errors agents)
**Feature**: branch `072-restore-slack-processing-reaction`
**Files**: lib/redmine_ai_helper/chat_channel/gateway.rb, test/unit/chat_channel/gateway_test.rb, docs/adr/053-processing-reaction-lifecycle.md, wiki/pages/chat-channel-gateway-architecture.md
**Category**: edge-case
**Related**: None

## Feedback

`Gateway#enqueue` checked `@shutdown_requested` and then called `show_processing`, which is a synchronous chat API call on the adapter's receive thread. It can take up to 10 seconds (HTTP timeout), or longer when Discord answers 429 and the adapter sleeps. If `shutdown` ran during that call, `SHUTDOWN` went into the queue first and the worker exited after it. The message was then pushed behind the marker: it was never processed, and its ⏳ was never removed. The window had been a few microseconds before. `adapter.stop` only closes the socket and does not cut off the HTTP call. This also contradicted ADR-053 ("a message dropped at shutdown never gets a mark") and FR-006 (no lost questions on a graceful stop).

## Original Code

```ruby
def enqueue(adapter, message)
  return if @shutdown_requested
  show_processing_safely(adapter, message)
  @queue << [ adapter, message ]
end
```

## Fix

`enqueue` checks `@shutdown_requested` again after `show_processing_safely`. If shutdown was requested in the meantime, it calls `clear_processing_safely` and returns without queueing. A new test makes `show_processing` call `shutdown` and asserts that the queue holds only `SHUTDOWN` and that `clear_processing` ran for the message. ADR-053 and the wiki page now describe the re-check.

## Root Cause

The AI placed the new call between an existing check and the action that check guards, and treated the check as still valid. It looked at the shutdown flag as a simple "drop late messages" guard. It did not ask how long the inserted code takes, or whether another thread (the signal handler's shutdown thread) can change the flag in the meantime. Its tests called `shutdown` before or after `enqueue`, never during the hook, so the interleaving was never tested.

## Prevention

When inserting blocking I/O (network, sleep, retries) between a check of shared state set by another thread and the action that check guards, re-check the state after the I/O, or move the I/O outside the check-then-act section. Add a test where the inserted call itself flips the state.

**Promoted to**: Not yet
