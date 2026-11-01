---
title: Chat Popup
type: component
sources: [S058]
updated: 2026-11-01
---

# Chat Popup

Part of the [AI Chat Sidebar](./chat-sidebar.md). The chat can be moved to a non-modal popup by moving the `#aihelper-sidebar`
element itself, never cloning it (ADR-064, S058). Open state and the unsent
draft are in `sessionStorage` (per tab); position and size are in
`localStorage` (survives closing the browser). All keys are per user (S058).
Not offered below 900px, where Redmine moves the sidebar into its flyout menu
(S058).

- Layout rules are pure functions in `ai_helper_chat_popup_layout.js`; the
  layout is saved once when a drag or resize ends having moved. A cancelled
  drag restores the earlier layout (S058).
- The default size is measured with the foldable area shown, and a 0 x 0
  measurement is not saved (S058).
- `aihelper-popup-pending` hides the chat until init, and is removed in a
  `finally` so an error never leaves it hidden (S058).
- The popup never changes the sidebar fold state: history jumps skip
  `fold_chat(false)` while in popup mode (S058).
- Copied `#sidebar` list and divider rules use `:where()` so the plugin's own
  conversation rules win (S058).
