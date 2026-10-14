# CRF-024: Progress tests could not fail or did not confirm the failure they simulated

**Date**: 2026-10-13
**Source**: Local AI review (`/speckit-review-run`, tests agent)
**Feature**: branch `073-chat-channel-progress`
**Files**: test/unit/chat_channel/progress_reporter_test.rb, test/unit/chat_channel/message_handler_test.rb, test/unit/chat_channel/base_adapter_test.rb
**Category**: test-gap
**Related**: CRF-006, CRF-010, CRF-017

## Feedback

- `inspect` override untested; the "token not in log" test passed whatever the reporter did; the FR-007 limit boundary was not pinned.
- Cross-layer failure tests did not check that the failing request was actually sent.
- No test for a non-callable `progress_proc` or for adapters that claim progress support without implementing it.

## Original Code

```ruby
@adapter.failures[:post] = RuntimeError.new("slack_error")   # reporter never reads the token
```

## Fix

Added tests for `inspect`, the exact-limit case, a non-`Handle` return, the message id in the delete log, undeclared errors propagating, the `progress_proc` guard, and an all-adapters contract test. The failure tests now assert the failing request was sent. The vacuous token test was removed.

## Root Cause

The AI wrote tests per requirement bullet (SC/FR) and did not check that each could fail when the behaviour broke; simulated failures were not asserted to have happened.

## Prevention

- For every test, name the one-line code change it would catch; if none, delete or rewrite it.
- A test that injects a failure asserts the injected call occurred.
- Boundary tests include the exact limit.

**Promoted to**: Not yet
