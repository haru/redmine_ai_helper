# CRF-080: Copied #sidebar CSS rules outranked the plugin's own rules, and print and touch behaviour were not carried over

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: assets/stylesheets/ai_helper.css
**Category**: edge-case
**Related**: CRF-033

## Feedback

- The `ul`, `ul li` and `hr` rules copied from Redmine's `#sidebar` for `#aihelper-sidebar.aihelper-popup-mode` have higher specificity than the plugin's `#aihelper-chat-conversation ul li` and `#aihelper-chat-clear hr`, so AI answers lost bullets and indentation in the popup only.
- Redmine's `@media print { #sidebar { display: none } }` no longer applied after the move to `<body>`, so the popup printed over the page.
- No `touch-action` was set, so touch drags were taken over by the browser and ended in `pointercancel`.
- A long history menu could not be reached in a fixed popup.

## Original Code

```css
#aihelper-sidebar.aihelper-popup-mode ul li { list-style-type: none; ... }   /* (1,1,2) */
```

## Fix

The copies are wrapped in `:where(...)` (specificity stays at element level), a print rule hides the popup, `touch-action: none` is set on the header and the handles, and the history menu scrolls inside itself. The CSS test asserts the copies start with `:where(`.

## Root Cause

R-002 listed the Redmine rules to copy but not how their specificity compares with the plugin's own rules, and moving an element out of `#sidebar` was treated as losing only the rules named in the research. The cascade between the copied rule and existing plugin rules was never compared, and print and touch behaviour were not on the checklist for a `position: fixed` element.

## Prevention

- When copying a selector-scoped rule to a new container, compute the specificity of the copy and of every existing plugin rule that targets the same elements, and keep the copy below them (for example with `:where()`).
- For an element moved out of its original container, list the `@media print` rules and input-modality rules (`touch-action`) of the original container and carry them over or record why not.

**Promoted to**: Not yet
