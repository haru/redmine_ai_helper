# CRF-096: Journal edit tests asserted what another layer guaranteed, or missed the guard

**Date**: 2026-11-03
**Source**: Local AI review (speckit-review-run: tests)
**Feature**: branch `feature/085-journal-edit-typo-completion`
**Files**: test/functional/ai_helper_controller_test.rb, test/functional/ai_helper_journal_edit_controls_test.rb, test/functional/ai_helper_wiki_typo_overlay_test.rb, test/unit/util/completion_journal_resolver_test.rb, test/unit/agents/issue_read_agent_test.rb, test/javascript/autocompletion/ai_helper_journal_edit_aids.test.js
**Category**: test-gap
**Related**: CRF-042, CRF-077, CRF-091, CRF-033

## Feedback

- The prompt test asserted `"John Smith"`, who is also the issue author, so it
  passed even if the writer was wrong.
- The placement test's precondition already had the controls at the target,
  and its fixture lacked the private-notes elements `_notes_form.html.erb`
  renders before the hook output.
- No test: the cap applied after the "earlier than" filter, the same-second
  tie-break while editing, the observer releasing forms, the full path from
  typing to the request body, module enabled but no `:view_ai_helper`, the
  wiki partial's labels.
- The "module disabled" test never asserted that the form was found, and the
  extraction helper silently fell back to the whole body.

## Original Code

```ruby
assert_includes @captured_prompt, "John Smith"
```

```js
expect(block.nextSibling).toBe(dom.controls); // before attach
```

## Fix

The prompt test asserts `helping user "John Smith"` and the absence of
`helping user "Redmine Admin"`. The fixture renders the private-notes
elements, and the test asserts the controls start elsewhere and move behind
the editor. Added the missing tests above, a resolver unit test, and made the
helper raise when its marker is missing (with a test). Guards were removed
once to confirm the tests fail.

## Root Cause

The AI picked expected values that were already true for other reasons and
built the fixture from the code under test instead of the ERB (CRF-042/077).
It listed behaviours per layer but did not check which layer's change each
test would catch.

## Prevention

For each assertion, ask which line of production code, if removed, makes it
fail; choose values that differ between the correct and the wrong code (a
writer who is neither the issue author nor the current user). Fixtures copy the
whole region of the ERB between the elements involved. Test helpers that parse
a response raise when they cannot find their anchor.

**Promoted to**: Not yet
