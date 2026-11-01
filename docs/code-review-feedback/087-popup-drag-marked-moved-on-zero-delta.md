# CRF-087: Popup drag was marked as moved on a pointermove with no coordinate change

**Date**: 2026-11-01
**Source**: GitHub Copilot (PR #544)
**Feature**: branch `feature/083-chat-form-popup` / PR #544
**Files**: assets/javascripts/chat/ai_helper_chat_popup.js, test/javascript/chat/ai_helper_chat_popup.test.js
**Category**: edge-case
**Related**: CRF-085

## Feedback

`moveDrag` set `moved` for every `pointermove`, so a zero-delta move wrote the layout on `pointerup`, contrary to the documented "only when the pointer moved" behaviour (https://github.com/haru/redmine_ai_helper/pull/544#discussion_r4434365096).

## Original Code

```js
const delta = { x: event.clientX - drag.x, y: event.clientY - drag.y };
drag.moved = true;
```

## Fix

`drag.moved = true` is set only when `delta.x !== 0 || delta.y !== 0`. A Vitest case presses, sends a `pointermove` at the same coordinates, releases, and asserts nothing is saved (it failed before the fix).

## Root Cause

The event name was treated as "the pointer moved". Browsers can dispatch `pointermove` for pressure/tilt changes or with identical coordinates, and the tests only covered a press-release without any move event.

## Prevention

- When a flag means "the value changed", derive it from comparing the values, not from the arrival of an event; add a test that fires the event with unchanged values.

**Promoted to**: Not yet
