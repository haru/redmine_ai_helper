# CRF-091: Tests asserted an outcome another layer already guaranteed, or could not tell whether the guard ran

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-tests)
**Feature**: branch `feature/084-project-management-tools`
**Files**: test/unit/tools/project_tools_test.rb, test/functional/ai_helper_mcp_controller_test.rb, test/unit/agents/project_agent_test.rb, test/unit/tools/no_delete_tools_assertions.rb, test/unit/tools/member_tools_test.rb, test/unit/tools/project_write_tools_test.rb
**Category**: test-gap
**Related**: CRF-006, CRF-010, CRF-033

## Feedback

The allowed-parents filter test excluded a descendant that Redmine removes anyway; the MCP read-only test called tools with `{}` so a missing-argument error looked like a guard rejection; backstory patterns such as `/confirm/i` matched unrelated lines; `assert_raises(Class, "msg")` did not check the message; the destructive-call regex missed `update(status:`, `send(:destroy)`, `clear`; several raise/guard branches had no driving test.

## Original Code

```ruby
assert_not_includes parent_ids, 3   # 3 is a descendant of project 1
post :handle_request, body: tools_call_payload(name, {}), as: :json
assert_equal true, body.dig("result", "isError")
```

## Fix

Tests now use a non-descendant project and flip the AI Helper scope (and were mutation-checked by removing the filter), call the MCP tools with valid arguments and assert the exact permission-denied text and unchanged rows, anchor each backstory pattern to its operation, check exception messages, extend `DESTRUCTIVE_CALL` with a self-test of caught and ignored spellings, and add the missing guard-branch tests.

## Root Cause

The AI wrote tests that passed with the implementation present and did not run them with the guard removed, and it picked fixture values without checking whether another layer already produced the same outcome. AGENTS.md (CRF-051) requires the mutation run and arranging input so only the guard can produce the result.

## Prevention

For each new guard, remove it once and confirm its test fails; choose fixtures that Redmine itself would not exclude; call MCP/tool entry points with valid arguments so only the guard can reject; assert full messages, not bare `isError` or `/confirm/`.

**Promoted to**: Not yet
