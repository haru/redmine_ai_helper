# CRF-077: "Move" tests passed without the move, and the fixture DOM did not match what the ERB renders

**Date**: 2026-10-29
**Source**: Local AI review (speckit-review-run, tests agent)
**Feature**: branch `bugfix/541-preview-control-position` (specs/082-fix-preview-control-position)
**Files**: test/javascript/autocompletion/ai_helper_issue_autocompletion.test.js, test/javascript/autocompletion/ai_helper_wiki_autocompletion.test.js
**Category**: test-gap
**Related**: CRF-042, CRF-051

## Feedback

- The FR-005 tests (no wiki toolbar, text format "none") ran the real scripts but could not fail. In the issue test the old fixture `createIssueDOM` already put the checkbox container right after the textarea and the test only asserted `display === "block"`; in the wiki test `createWikiDOM` also placed the container right after the textarea and the test asserted `nextSibling === null`. If the script had never moved the container, both still passed. Only the helper's own unit test checked the fallback position.
- `createJstIssueDOM` always built both `#ai-helper-duplicate-check-container` and `#ai-helper-notes-checkbox-container`. `shared/_textarea_overlay.html.erb` renders the duplicate-check container only for a new issue (`@issue&.new_record?`) and the notes container only for a persisted one (`@issue&.persisted?`). In the edit-form tests the script therefore moved a duplicate-check container that does not exist in production.
- `createJstWikiDOM` said the textarea "sits directly in the form". `app/views/wiki/edit.html.erb` (lines 15-16) puts it in `div.box.tabular` inside `form#wiki_form`.

## Original Code

```js
// wiki fixture: container already adjacent to the textarea
parent.appendChild(textarea);
parent.appendChild(checkboxContainer);
...
expect(dom.checkboxContainer.nextSibling).toBeNull();   // true before the script runs
```

```js
// issue fixture: both containers built for every page type
const dupContainer = ...("ai-helper-duplicate-check-container");
const notesContainer = ...("ai-helper-notes-checkbox-container");
```

## Fix

- The no-toolbar fixtures (`createPlainIssueDOM`, `createWikiFormDOM({ withToolbar: false })`) render the container in the hook area, outside the editor, as the hooks do. The tests first assert the precondition (the textarea has no container next to it), run the real script, then assert the container is the textarea's next element and visible.
- Mutation check: replacing the helper call with only `style.display = 'block'` makes the FR-005 tests and the #541 tests fail (5 and 2 failures in the issue and wiki files).
- `createJstIssueDOM({ persisted })` builds the notes editor and notes container only for a persisted issue, and the duplicate-check container only for a new issue. The edit-form test now also asserts the description container placement, so a mix-up between the two editors fails.
- The wiki fixture wraps the editor in `div.box.tabular` inside `form#wiki_form`.

## Root Cause

The new tests were written next to existing characterization tests whose fixtures put the container beside the textarea, and the fixture was extended from what the script touches, not transcribed from the ERB for each page type (CRF-042 already says this). A "moves X to Y" test also never asserted that X was not already at Y before the script ran, so the expected result could come from the fixture alone (the CRF-051 problem: the outcome reachable from another layer). The guard-removal check was run for the toolbar branch but not for the fallback branch through the real scripts.

## Prevention

- A test that checks an element was moved asserts, before running the code, that the element is not already in the target position, and places the element where the production hook or ERB renders it.
- A fixture builder renders an element only for the page types where the ERB renders it (read the `if` conditions around it in the partial) and nests the element exactly as the production ERB does, including wrapper elements.
- After writing such a test, run it once with the move removed and confirm it fails.

**Promoted to**: AGENTS.md
