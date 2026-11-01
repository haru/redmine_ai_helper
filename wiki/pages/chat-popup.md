---
title: Chat Popup
type: component
sources: [S058]
updated: 2026-11-01
---

# Chat Popup

Part of the [AI Chat Sidebar](./chat-sidebar.md). The chat can be moved to a
non-modal popup that is movable, resizable, stays open across page navigation
and returns to the sidebar when the tab is closed. Design rationale and
rejected alternatives: [Chat Popup Design Decisions](./chat-popup-design-decisions.md).

## Structure
- The `#aihelper-sidebar` element itself is moved to `document.body` and gets
  `aihelper-popup-mode` (`position: fixed`); closing moves it back to the top
  of `#sidebar-wrapper`. It is never cloned, because the chat scripts use fixed
  IDs such as `aihelper-chat-conversation` (ADR-064, S058).
- Layout rules are pure functions in `ai_helper_chat_popup_layout.js`; DOM and
  state wiring is a second file, called from two lines in `ai_helper_chat.js`.
  No DB column, route or controller changes (S058).
- Not offered below 900px (`matchMedia('(max-width: 899px)')`), where Redmine
  moves the sidebar into its flyout menu; the icon is hidden by CSS, and a popup
  open when the width drops returns to the sidebar with its open state kept
  (S058).
- A page without the AI Helper sidebar shows no popup, even if the open state is
  saved; it returns on the next page that has the sidebar (S058).

## State
- `sessionStorage` (per tab): open state and the unsent draft. `localStorage`:
  position and size, surviving a browser restart. Keys include the user ID
  (`aihelper-popup-open_`, `-draft_`, `-layout_`) (S058).
- The draft is saved once on `pagehide`, because command completion, choice
  buttons and `form.reset()` change the input without an `input` event. An input
  not yet loaded leaves the old draft alone; an empty input removes it (S058).
- Gotcha: MDN documents that a tab opened with an `opener` starts with a copy of
  its `sessionStorage` and that a restored tab keeps its session, so the popup
  state may survive there; duplicating a tab is not documented (S058).
- On `pageshow` with `persisted` (back/forward cache) the mode, layout and draft
  are re-synchronised from storage (S058).

## Layout
- Move and resize use Pointer Events and `setPointerCapture`: the header moves,
  eight ERB-rendered elements resize. The layout is saved once, on `pointerup`,
  only if the pointer moved; `pointercancel` and `lostpointercapture` restore
  the earlier layout and save nothing (S058).
- Default size is the measured sidebar size, measured with the foldable area
  shown; offset 24px left and 24px down; minimum 240 x 240px. It is saved on the
  first open. A 0 x 0 measurement is not saved. A layout that no longer fits the
  viewport is fitted for display, and the fitted value is not saved (S058).
- `z-index` is 1001 (above Redmine's sticky issue header at 1000) and 90 while
  `.ui-widget-overlay` exists so Redmine's modal dialogs (100) stay usable;
  plugin overlays at 9998-10001 stay on top (S058).

## Gotchas
- `aihelper-popup-pending` on `<html>` hides the chat until init to avoid a
  flash; it is removed in a `finally` so an error never leaves it hidden (S058).
- The popup never changes the sidebar fold state: history jumps skip
  `fold_chat(false)` while in popup mode (S058).
- Rules that only apply inside Redmine's `#sidebar` (font size, `hr`, `ul`, and
  `@media print`) are copied for `.aihelper-popup-mode`, inside `:where()` so the
  plugin's own conversation rules win. Changes to those Redmine rules need the
  same change here (S058).
- With only the AI Helper in the sidebar, an empty sidebar area remains while the
  popup is open (S058).
- A navigation during streaming is left to the existing `reload_chat`, which
  shows the saved conversation (S058).
