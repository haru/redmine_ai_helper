# CRF-006: Paused-chat guard added without a test that exercises it

**Date**: 2026-10-11
**Source**: GitHub Copilot (PR #499)
**Feature**: branch `feature/069-ruby-llm-2-1-migration` / PR #499
**Files**: lib/redmine_ai_helper/assistant.rb, lib/redmine_ai_helper/base_agent.rb, test/unit/assistant_test.rb, test/unit/base_agent_test.rb
**Category**: test-gap
**Related**: CRF-003

## Feedback

The `waiting?` guards in `Assistant#run` and `BaseAgent#chat` were never exercised: every test stubbed `waiting?` to `false`, so removing or inverting the guard would leave the suite green.
([r4240337257](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337257), [r4240337287](https://github.com/haru/redmine_ai_helper/pull/499#discussion_r4240337287))

## Original Code

```ruby
mock_chat_instance.stubs(:waiting?).returns(false)  # in every test
```

## Fix

Added tests with `waiting? == true` for `Assistant#run`, `BaseAgent#chat`, and the streaming path of `BaseAgent#chat`, asserting that the error propagates.

## Root Cause

When fixing CRF-003 the AI added the guard and then only made existing mocks satisfy the new `waiting?` call (stubbing `false`) so the suite passed. It did not apply CRF-003's own prevention rule ("tests must assert that errors propagate") to the new branch.

## Prevention

Every new `raise`/guard branch must come with a test that drives the condition to true and asserts the error. Stubbing a new predicate only to its "happy" value in existing tests is not coverage; add the opposite case in the same change (for both streaming and non-streaming paths when the method has both).

**Promoted to**: AGENTS.md
