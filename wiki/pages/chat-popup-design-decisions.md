---
title: Chat Popup Design Decisions
type: decision
sources: [S058, S059]
updated: 2026-11-01
---

# Chat Popup Design Decisions

Why the [Chat Popup](./chat-popup.md) is built the way it is (ADR-064, S058).
Each line is a rejected alternative and the reason.

- **`position: fixed` inside `#sidebar-wrapper`**: Redmine hides the wrapper
  with `#main.collapsedsidebar #sidebar-wrapper { display: none; }`
  (`application.css:377`), so the popup would vanish with it (S058).
- **A second chat form**: duplicates the element IDs the chat scripts rely on
  (S058).
- **A shared look defined anew for sidebar and popup**: drifts from Redmine's own
  sidebar styles; the Redmine rules are copied instead (S058).
- **`localStorage` or the server session for open state**: not per tab, so a new
  tab would open as a popup (S058).
- **Saving the draft on each `input` event**: every programmatic path that
  changes the value would need its own handling (S058).
- **Deciding the open state on the server**: the server cannot read
  `sessionStorage`, hence the inline script in `_html_header.html.erb` that
  reads it synchronously (S058).
- **One fixed `z-index`**: above 100 covers Redmine's modal dialogs; below 1000
  hides the close button behind the sticky header (S058).
- **jQuery UI draggable/resizable, or CSS `resize`**: jQuery is not allowed in
  the plugin and `resize` only offers the bottom-right corner (S058).
- **Measuring the default layout on every page**: conversation length and sidebar
  width differ per page, so the popup would move between pages (S058).
- **Checking the flyout toggle button's visibility**: depends on the order in
  which Redmine's `resize` handler runs, so a media query is used (S058).

Redmine's flyout moves `#sidebar > *` (`responsive.js:57`), so returning the
element to `#sidebar-wrapper` also puts it back in the menu (S058).

## Closing animation (ADR-065, S059)
- **Waiting for `transitionend`**: it is not fired when no value changes or the
  element is hidden, so the chat could stay in the body (S059).
- **Moving the chat back to measure the slot**: each move drops focus and the
  scroll position and costs a second layout (S059).
- **Animating the position only**: the user chose to restore the size too (S059).
- **Deleting the saved state after the animation**: a navigation in the 200ms
  would reopen the popup (S059).
