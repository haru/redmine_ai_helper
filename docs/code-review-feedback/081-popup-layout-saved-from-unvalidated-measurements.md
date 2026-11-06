# CRF-081: Popup layout was saved from measurements and fitted values that were not valid saved values

**Date**: 2026-11-01
**Source**: Local AI review (speckit-review-run: code, comments, tests, errors, types, simplify agents)
**Feature**: branch `feature/083-chat-form-popup` (specs/083-chat-form-popup)
**Files**: assets/javascripts/chat/ai_helper_chat_popup.js, assets/javascripts/chat/ai_helper_chat_popup_layout.js
**Category**: edge-case
**Related**: CRF-014

## Feedback

- With a folded sidebar the default layout measured the header-only height (R-008 requires the expanded height) and saved it.
- A default measured as 0 x 0 (collapsed sidebar) was saved although `isValidLayout` rejects it.
- A press on the header without movement saved the fitted layout and overwrote the original; a header drag saved the shrunken width and height.
- `pointercancel` saved a partial layout although R-007 says save on `pointerup` only.
- Resizing in a viewport shorter than 240px saved a size below the minimum; a window resize during a drag left a stale start layout.
- Returning from the back/forward cache kept the cached position and draft.

## Original Code

```js
const rect = chatElement().getBoundingClientRect();
...
localStorage.setItem(key, JSON.stringify(currentLayout()));   // inline styles, fitted or not
```

## Fix

The default is measured with the foldable area shown and saved only when valid; a drag saves only when the pointer moved, keeps the saved size of an axis the user did not change, and `pointercancel`/`lostpointercapture` restore the start layout without saving. Resizing lets the minimum win, a window resize ends the drag, and `pageshow` with `persisted` re-applies mode, layout and draft. The pure rules moved to `ai_helper_chat_popup_layout.js`.

## Root Cause

The write path was written from the read path's rules (what is displayed) and inline styles were used as the state store. Validation existed only on read, and the spec sentence 'the fitted value is not saved' was applied to `open()` and `resize` but not traced through every other writer.

## Prevention

- Every writer of a persisted value goes through the same validator as the reader, and a value derived for display (fitted, measured while hidden) is never read back from the DOM and saved.
- For each 'not saved' sentence in a spec, list every code path that calls the save and check it against the sentence.

**Promoted to**: Not yet
