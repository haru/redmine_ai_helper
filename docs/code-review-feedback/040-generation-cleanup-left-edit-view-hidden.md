# CRF-040: Generation cleanup un-hid the result area but not the view that startEdit had hidden

**Date**: 2026-10-17
**Source**: Local AI review (spec review: code/comments/tests/errors/simplify, `specs/077-fix-dashboard-health-report-error/review.md`)
**Feature**: branch `bugfix/077-fix-dashboard-health-report-error`
**Files**: assets/javascripts/project_health/ai_helper_project_health_actions.js, test/javascript/project_health/ai_helper_project_health_actions.test.js
**Category**: edge-case
**Related**: SF-013, CRF-024, CRF-033

## Feedback

Starting a generation while the edit form was open left the detail pane blank until the history reload: `startEdit` hides the whole `.ai-helper-health-report-view` (the result area's parent), but `clearPreviousReportDetails` only set `resultDiv.hidden = false`. The loader and the stream — and the `onerror` message — were rendered inside the still-hidden view, so the user saw nothing, contrary to the spec's assumption that the output is visible.

## Original Code

```js
  // The result area is hidden while the original report is shown.
  resultDiv.hidden = false;
```

## Fix

`clearPreviousReportDetails` now also un-hides the `.ai-helper-health-report-view` found via the report body. The "show loading state" comment was moved below the cleanup call and the `contentContainer` lookup next to its use. The test helper gained an `editFormOpen` state; the new test starts from "view hidden, form shown" and asserts that the result area and every element between it and the document has `hidden === false`, that the result area is still the element in the document, and that the loader is inside it.

## Root Cause

The cleanup was written against one UI path only: `toggleOriginal`, which hides the result area itself. The other path that hides the same subtree, `startEdit`, hides the parent view, and the AI never grepped who else sets `hidden` on that element. The test helper reproduced the same single state ("original shown"), so the gap was invisible to the suite.

## Prevention

When a routine resets a hidden/shown state, first grep every place that sets that state on the element or its ancestors, and drive one test per source state; each test must assert that the element and its ancestors are attached (`contains`, `getElementById`) and not hidden — not only that a `querySelector` returns null.

**Promoted to**: Not yet
