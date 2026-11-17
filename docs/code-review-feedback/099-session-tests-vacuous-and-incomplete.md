# CRF-099: Session persistence tests asserted what they had just written and left a spec scenario and helper failure modes uncovered

**Date**: 2026-11-17
**Source**: Local AI review (speckit-review-run: code, tests, errors, types, simplify agents)
**Feature**: branch `bugfix/086-fix-session-conversation-id`
**Files**: test/functional/ai_helper_controller_test.rb, test/integration/ai_helper_session_persistence_test.rb
**Category**: test-gap
**Related**: CRF-091, CRF-096, CRF-077

## Feedback

- The FR-004 functional test used a bare `assert_raises(NoMethodError)`. It also passes with the old code (`nil[:conversation_id] = id` raises too) and with any unrelated `NoMethodError`, so it did not show that the new guard ran.
- `display_conversation` wrote a value into the stored session and then asserted that same value back, which cannot fail. The precondition that matters (the stored session does not already point at the conversation about to be selected) was not checked.
- US1 scenario 3 (reload after the messages shows the conversation) had no test step.
- `stored_session` used `find`, so it silently returned the first matching session, or `nil` and a `NoMethodError` in the caller when none matched.

## Original Code

```ruby
assert_raises(NoMethodError) { @controller.send(:set_conversation_id, @conversation.id) }

def display_conversation(conversation)
  stored_session["ai_helper"] = { conversation_id: conversation.id }
  assert_equal conversation.id, stored_session["ai_helper"][:conversation_id]
end

def stored_session
  ChangeDetectingStore.storage.values.find { |data| data["user_id"] }
end
```

## Fix

- The functional test captures the error and asserts `error.name == :merge` and `error.receiver` is `nil`.
- The tautological assert was removed. `assert_not_equal conversation_a.id, stored_session["ai_helper"][:conversation_id]` now runs before the `conversation` GET.
- The new-conversation test ends with a `reload` request and checks that the second message and its answer are shown.
- `stored_session` selects all logged-in sessions and asserts that exactly one exists.

## Root Cause

The AI wrote assertions that looked like checks but read back what the test had just set, or that another layer would also satisfy. AGENTS.md already says to arrange the input so only the guard can produce the outcome (CRF-051) and to check that a precondition is not already at the target (CRF-042); the AI applied these to the main scenario but not to the helper and the guard test. It also did not map each acceptance scenario of the spec to a test step.

## Prevention

For each new assertion, name what could make it fail: an assertion on a value the test wrote one line earlier, or one the old code also satisfies, is replaced by a check on the exception's name and receiver or on state before the action. Before finishing a test file, list the spec's acceptance scenarios and confirm each has a step. A test helper that looks up state asserts that exactly one match exists.

**Promoted to**: Not yet
