# ADR-065: Animate the chat popup closing as the reverse of opening

**Date**: 2026-11-01
**Status**: Accepted

## Context

ADR-064 moves `#aihelper-sidebar` between the sidebar and `document.body`.
Opening animates the position over 200ms (FR-018), but closing returned the
chat at once. FR-019 asks for the reverse animation on close, including the
size (`specs/083-chat-form-popup/`, R-012). ADR-064 is append-only, so this
decision is recorded separately.

## Decision

- **Animate, then move** (R-012). `close()` adds `aihelper-popup-animating`,
  changes `left`, `top`, `width` and `height` to the sidebar slot over 200ms, and
  calls `hide()` (the ADR-064 move back to `#sidebar-wrapper`) from a
  `setTimeout`. The transition in `ai_helper.css` lists all four properties, so
  opening and closing share it.
- **Slot**: position and width come from the rectangle of `#sidebar-wrapper`; the
  height is the sidebar height measured by `show()`, because the chat has no
  height while it is the popup.
- **Saved state is removed at the start**. The open state and the draft keys are
  deleted when `close()` is called, not when the animation ends, so a navigation
  during the animation does not restore the popup.
- **No re-entry**. A `closing` flag makes a second `close()` and a header drag
  do nothing during the animation. `hide()` clears the flag and advances
  `animationToken`, so a pending close timer never moves a popup that was opened
  again.
- **Automatic closes do not animate**. The narrow-screen change and the
  `pageshow` re-synchronisation call `hide()` directly.

## Consequences

- `close()` is asynchronous in effect: the chat is in the sidebar 200ms after
  the call. Tests advance fake timers (`closeAndFinish`).
- A chat that was folded in the sidebar when the page was restored shrinks to the
  folded height, because that is the height `show()` measured.
- Opening during the animation is ignored, because the chat is still in popup
  mode.

## Alternatives Considered

- **Waiting for `transitionend`** (R-012): not fired when no value changes or
  the element is hidden, so the chat could stay in the body.
- **Moving the chat back to measure the slot, then forward again** (R-012): each
  move drops focus and the scroll position and costs a second layout.
- **Animating the position only** (R-012): the user chose to restore the size
  too.
- **Deleting the saved state after the animation** (R-012): a navigation in the
  200ms would reopen the popup.
