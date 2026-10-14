# CRF-004: Spec-assumed with_end_user does not send the user ID on the OpenAI Responses protocol

**Date**: 2026-10-11
**Source**: Local AI review (speckit-review-run)
**Feature**: branch `feature/069-ruby-llm-2-1-migration`
**Files**: lib/redmine_ai_helper/llm_client/base_provider.rb, test/unit/llm_client/*_test.rb, specs/069-ruby-llm-2-1-migration/research.md (R7-d)
**Category**: other
**Related**: None

## Feedback

The "send user ID" setting silently did nothing for OpenAI and OpenAI-compatible profiles: RubyLLM 2.1's default Responses protocol does not override `apply_end_user`, so the base implementation drops the value at debug level.

## Original Code

```ruby
chat.with_end_user(User.current.id.to_s)
```

## Fix

`apply_user_identifier` now calls `chat.with_provider_options(safety_identifier: id)`, which is merged into the payload for every protocol. Tests expect `with_provider_options`. The ADR-049 consequences note the change; specs/069 still needs updating.

## Root Cause

The AI followed research R7-d, which verified only the Chat Completions protocol's `apply_end_user`, and the tests mocked `with_end_user`, so they proved only that the method was called. Nobody checked the protocol actually used by default.

## Prevention

When mapping an old option to a new library API, read the implementation for every protocol/provider path that will be used by default and verify the request payload (e.g. `Chat#render`), not just that the new method exists. Do not accept a spec claim about library behaviour without checking the default code path.

**Promoted to**: Not yet
