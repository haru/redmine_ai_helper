---
title: Chat Popup
type: component
sources: [S058, S059, S063]
updated: 2026-11-21
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
- Opening moves the chat from its sidebar position to the layout over 200ms
  (FR-018, left/top only). Closing is the reverse (FR-019, ADR-065, S059): the
  position and size change to the sidebar slot over 200ms, then the chat returns
  to `#sidebar-wrapper`. The saved open state and draft are removed when
  `close()` is called, so a navigation during the animation does not reopen the
  popup. A second `close()` and header drags are ignored while closing. Narrow
  screens and `pageshow` return the chat at once, without animation (S059).
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

## Layout & gotchas

Layout rules and the popup's gotchas are on a separate page. See [Chat Popup Layout & Gotchas](./chat-popup-layout-and-gotchas.md) (S058, S063).

