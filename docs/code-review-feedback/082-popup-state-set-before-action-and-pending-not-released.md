# CRF-082: Popup state was saved before the action succeeded, and a startup error left the chat hidden

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: assets/javascripts/chat/ai_helper_chat_popup.js, assets/javascripts/chat/ai_helper_chat.js
**Category**: error-handling
**Related**: CRF-069

## Feedback

- `open()` saved the open state before `show()`; if `show()` threw, every later page in the tab tried to restore a popup that could not open.
- `aihelper-popup-pending` (which hides the chat) was removed at the end of `init()` and `initSidebar()` only, so any thrown error left the chat invisible with no way to recover.

## Original Code

```js
sessionStorage.setItem(storageKey('aihelper-popup-open'), 'true');
show(true);
...
applyState();
document.documentElement.classList.remove('aihelper-popup-pending');
```

## Fix

The state is saved after `show()` succeeds, and the pending class is removed in a `finally` in both `init()` and `initSidebar()` (the error still surfaces). Tests drive both failures.

## Root Cause

The specs prescribed 'remove the class when initialization completes' and nothing for failure; the 'surface errors' rule was applied to the catch side but the cleanup of a temporary hidden state on the failure path was not considered.

## Prevention

- Persist state after the action it describes has succeeded.
- A temporary state that hides UI (class, flag, overlay) is released in a `finally`; the error is not caught.

**Promoted to**: Not yet
