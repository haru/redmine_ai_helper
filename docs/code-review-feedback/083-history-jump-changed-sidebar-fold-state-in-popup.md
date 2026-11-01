# CRF-083: A shared history action changed the sidebar fold state while the chat was the popup

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: assets/javascripts/chat/ai_helper_history.js
**Category**: edge-case
**Related**: CRF-069

## Feedback

`jump_to_history` always calls `ai_helper.fold_chat(false)`, which writes the sidebar fold flag and animates the foldable area. Opening a history entry in the popup unfolded a folded sidebar, against the spec ('the popup does not change the sidebar fold state'). The test 'never writes the sidebar fold state' covered only open and close.

## Original Code

```js
ai_helper.close_dropdown_menu();
ai_helper.fold_chat(false);
```

## Fix

`fold_chat(false)` is skipped when the conversation is inside `.aihelper-popup-mode`; a test drives the history jump in the popup.

## Root Cause

The popup was built by moving the element so existing scripts keep working, and 'existing scripts keep working' was taken to mean 'existing scripts have no side effect that matters'. The callers of `fold_chat` were not grepped (AGENTS.md: check every caller of a shared path).

## Prevention

- When a feature promises not to change a state, grep every writer of that state and check each one in the new context, not only the new feature's own code.

**Promoted to**: Not yet
