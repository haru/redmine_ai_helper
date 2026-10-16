# SF-013: Assumed the edit-form state was unaffected by the clipping bug without measuring it

**Date**: 2026-10-15
**Feature**: specs/075-fix-health-report-clipping (branch `bugfix/075-fix-health-report-clipping`)
**Artifact**: spec.md (Edge Cases, FR-008, SC-003)
**Category**: unconfirmed-assumption
**Related**: SF-008, SF-009, SF-014

## Feedback

During `/speckit-plan`, the AI measured the dashboard detail pane with the edit form open and found that the form was already clipped before the fix. It asked whether the fix should also cover this state. The user answered: "Yes, that is fine" (fix it as part of this change).

## What the AI Wrote

- Edge Cases: "Edit form open: as before the fix, the textarea, the Save/Cancel buttons and the export links are all visible. This fix must not make it worse."
- FR-008 listed "the detail pane with the edit form open" among the views that must not change.
- SC-003: "In the views and states listed in FR-008, there is no visual difference before and after the fix."

## Correction

- The edit-form edge case now requires the textarea, the buttons and the export links to be visible inside the detail pane without scrolling inside the report frame. It notes that before the fix, at 1280x600 and 1280x800, the Save button and the export links were hidden (232px / 108px).
- The edit-form state was removed from FR-008.
- SC-003 now also requires 0px clipping of the Save button and the export links at 1280x600/800/1080 with the edit form open.
- A plan-time clarification records the decision.

## Root Cause

The AI based the edit-form statements on the issue reporter's sentence: "When I click Edit, everything looks fine". It then turned that sentence into a "do not change" requirement. While writing the spec it measured the clipping on a real browser, but only for the read-only view (the table in the Background section). It did not repeat the measurement with the edit form open, even though the form sits in the same height-limited frame. In fact, the pane's `overflow: hidden` also hid the form's lower part at common screen heights. The reporter's environment was unknown, so the claim only held for their screen size.

## Prevention

When a spec marks an existing state as "unchanged" or "already working" in a bug fix, measure that state the same way as the broken one (same screen sizes, same data) before writing the requirement. A user report alone is not enough. If the state cannot be measured, write it as an assumption and ask.

**Promoted to**: Not yet
