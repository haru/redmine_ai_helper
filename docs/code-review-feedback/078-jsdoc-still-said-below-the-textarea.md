# CRF-078: JSDoc kept the old placement wording after the placement changed

**Date**: 2026-10-29
**Source**: Local AI review (speckit-review-run, comments agent)
**Feature**: branch `bugfix/541-preview-control-position` (specs/082-fix-preview-control-position)
**Files**: assets/javascripts/autocompletion/ai_helper_issue_autocompletion.js, assets/javascripts/shared/ai_helper_editor_controls.js
**Category**: doc-comment
**Related**: None

## Feedback

The JSDoc of `initializeDescriptionAutoCompletion` ("move its checkbox into place below the textarea") and `initializeNotesAutoCompletion` ("below the textarea") became wrong when the checkbox moved below the whole editor, which is the exact distinction issue #541 is about. The inline comments next to the changed calls had already been updated. The `placeAfterEditor` description ("below the editor of `textarea`") did not say what "the editor" is.

## Original Code

```js
/**
 * Initialize description-field auto-completion and move its checkbox
 * into place below the textarea.
 */
```

## Fix

Both function docs now say "below the description editor" / "below the notes editor". The helper doc says: "Move `container` right after the textarea's `.jstBlock` (or right after the textarea itself when there is no toolbar) and reveal it."

## Root Cause

The edit touched the line inside each function and the inline comment, and stopped there. The doc block above the function describes the same behaviour in the same words, but the search for the old wording ("below the textarea") was not run over the whole file, so the doc blocks were not found.

## Prevention

When a change alters where something is placed or what a function does, grep the changed file (and its tests) for the old wording of that behaviour (here "below the textarea", "after the textarea") and update every doc block and comment that still states it, in the same change.

**Promoted to**: Not yet
